package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"domix/backend/internal/ratelimit"
)

// the one-time code login: a number is typed in the app, a code is delivered to it, and typing that
// code back is the proof of ownership that mints a jwt.
//
// **the pending codes live in ram and deliberately not in postgres**, for the same reason the
// telegram handshake's sessions do (see session.go): a signup that is abandoned between "send me a
// code" and "here is the code" must leave nothing behind. a codes table would collect a row per
// abandoned attempt, each one holding a phone number nobody asked us to keep, and would need its own
// sweeper anyway. the cost of keeping them in ram is that a restart invalidates every code in
// flight, which asks a handful of users to press "send again" - the right side of that trade while
// this is one process.
//
// a mutex and a plain map rather than session.go's sync.Map, and that difference is load-bearing:
// every wrong guess has to *increment a counter on an existing entry*, which is a read-modify-write.
// sync.Map can only do that as Load-then-Store, so two guesses arriving together would both read 2,
// both write 3, and the third wrong guess would never happen - the attempt cap would leak an extra
// try per concurrent request. ratelimit.Limiter is built this way for the same reason.

// the four numbers that keep this flow from costing money. every send is paid for (CLAUDE.md §3,
// ~150 000 SMS budgeted for the year), so these are correctness, not hardening.
const (
	// six digits is what every uzbek service sends and what the sms template is moderated around.
	// it is only 10^6 possibilities, which is why MaxCodeAttempts exists: guessing is stopped by the
	// attempt cap, not by the length.
	CodeLength = 6

	// long enough to walk from the map screen to the sms app, short enough that a code seen over a
	// shoulder is worthless by the time anyone acts on it.
	CodeTTL = 5 * time.Minute

	// wrong guesses before the entry dies and the user has to pay for a new code. with 10^6 codes
	// and three tries, a guessing attack needs ~333 000 sends to expect one hit.
	MaxCodeAttempts = 3

	// how long "отправить ещё раз" stays disabled. the app shows this as a countdown.
	ResendCooldown = 60 * time.Second

	// the per-phone ceiling underneath the cooldown. the cooldown alone only forces an attacker to
	// wait a minute between sends, which is still ~1400 paid messages a day aimed at one number;
	// this bucket caps a single number at five quick attempts and then one per hour.
	phoneSendBurst  = 5
	phoneSendRate   = 1.0 / 3600.0 // one refill per hour
	phoneSendMemory = 24 * time.Hour

	// how often the sweeper walks the map. codes live five minutes, so this is fine-grained enough
	// that an expired code is gone long before anybody could have typed it.
	codeSweepInterval = 30 * time.Second
)

// what can go wrong, as sentinels rather than strings: endpoints.PhoneAuth turns each one into its
// own machine-readable code, and the flutter side switches on that code to pick a message.
var (
	ErrNoPendingCode   = errors.New("auth: no code was requested for this number")
	ErrCodeExpired     = errors.New("auth: the code has expired")
	ErrCodeMismatch    = errors.New("auth: that is not the code we sent")
	ErrTooManyAttempts = errors.New("auth: too many wrong attempts, the code is dead")
	ErrResendTooSoon   = errors.New("auth: a code was sent to this number moments ago")
	ErrSendBudget      = errors.New("auth: too many codes have been sent to this number")
)

// Pending is what a correct code proves: this caller controls this number, and these are the name
// and role they asked to register with. It is the whole reason the name and role travel with the
// *request* for a code rather than with the verification - by the time the code comes back there is
// no screen left to ask on.
type Pending struct {
	Phone string // canonical, 998XXXXXXXXX
	Name  string
	Role  string
}

// CodeManager holds every code that has been sent and not yet used.
type CodeManager struct {
	mu      sync.Mutex
	pending map[string]*pendingCode // canonical phone -> the code in flight for it

	// the per-phone send budget. it is created here rather than passed in, so there is no way to
	// build a manager without the guard that stands between a bug and the sms bill.
	budget *ratelimit.Limiter
}

type pendingCode struct {
	// **the code itself is never stored.** what is kept is sha256(salt || code), so a heap dump, a
	// core file or a debugger attached to this process yields nothing that can be typed into the
	// verify endpoint. the salt is per-entry because six digits is a 10^6 space - an unsalted digest
	// would be reversible by brute force in milliseconds.
	salt   [16]byte
	digest [32]byte

	name     string
	role     string
	attempts int
	issuedAt time.Time
}

func NewCodeManager() *CodeManager {
	m := &CodeManager{
		pending: make(map[string]*pendingCode),
		budget:  ratelimit.New(phoneSendRate, phoneSendBurst, phoneSendMemory),
	}

	// same shape as SessionManager's sweeper: one goroutine, forever, evicting on age. without it
	// the map is a slow leak of phone numbers, since a user who never types the code leaves an entry
	// nothing else deletes.
	go m.sweep(codeSweepInterval, CodeTTL)

	return m
}

// Issue mints a code for this number and remembers its hash. The returned code is the only copy
// that ever exists in plaintext, and the caller's single job is to hand it to a verify.Sender.
//
// The second return value is how long is left on the cooldown, and it is meaningful only alongside
// ErrResendTooSoon - the app renders it as a countdown, so a user who already has the sms is not
// told to "try again later" with no idea how much later.
func (m *CodeManager) Issue(phone, name, role string) (code string, wait time.Duration, err error) {
	code, err = newCode()
	if err != nil {
		return "", 0, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// the cooldown is checked before the budget, so a user tapping the button twice spends no token
	if existing, live := m.pending[phone]; live {
		if since := time.Since(existing.issuedAt); since < ResendCooldown {
			return "", ResendCooldown - since, ErrResendTooSoon
		}
	}

	if !m.budget.Allow(phone) {
		return "", 0, ErrSendBudget
	}

	entry := &pendingCode{name: name, role: role, issuedAt: time.Now()}
	if _, err := rand.Read(entry.salt[:]); err != nil {
		return "", 0, fmt.Errorf("auth: no randomness for a code salt: %w", err)
	}
	entry.digest = hashCode(entry.salt, code)

	// a new code replaces the old one outright, attempts and all: two live codes for one number
	// would double the chance of a blind guess and there is no honest reason to have both.
	m.pending[phone] = entry

	return code, 0, nil
}

// Verify checks a typed code and, if it is right, hands back what the code was proving. The entry is
// consumed either way it ends - one code, one login - so a correct code cannot be replayed and a
// dead one cannot be guessed at forever.
func (m *CodeManager) Verify(phone, code string) (Pending, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	entry, live := m.pending[phone]
	if !live {
		return Pending{}, ErrNoPendingCode
	}

	// checked here as well as in the sweeper: the sweeper runs on a timer, so between two of its
	// passes an expired entry is still sitting in the map.
	if time.Since(entry.issuedAt) > CodeTTL {
		delete(m.pending, phone)
		return Pending{}, ErrCodeExpired
	}

	// constant time, so the comparison itself says nothing about how much of the digest matched.
	// digests do not leak the way plaintext would, but the check costs nothing and it is the habit
	// that matters the day something longer than a hash is compared here.
	digest := hashCode(entry.salt, code)
	if subtle.ConstantTimeCompare(digest[:], entry.digest[:]) != 1 {
		entry.attempts++
		if entry.attempts >= MaxCodeAttempts {
			delete(m.pending, phone)
			return Pending{}, ErrTooManyAttempts
		}
		return Pending{}, ErrCodeMismatch
	}

	delete(m.pending, phone)
	return Pending{Phone: phone, Name: entry.name, Role: entry.role}, nil
}

// Drop forgets a pending code. It exists for one caller: the endpoint, when the provider refused to
// deliver the message. Leaving the entry there would hold the user in a sixty-second cooldown
// waiting for a code that is never coming.
//
// The budget token stays spent, deliberately - a refused send may still have been billed, and the
// failure mode worth protecting against is a provider erroring on every call while we keep paying.
func (m *CodeManager) Drop(phone string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.pending, phone)
}

func (m *CodeManager) sweep(interval, ttl time.Duration) {
	for range time.Tick(interval) {
		cutoff := time.Now().Add(-ttl)

		m.mu.Lock()
		for phone, entry := range m.pending {
			if entry.issuedAt.Before(cutoff) {
				delete(m.pending, phone)
			}
		}
		m.mu.Unlock()
	}
}

func hashCode(salt [16]byte, code string) [32]byte {
	h := sha256.New()
	h.Write(salt[:])
	h.Write([]byte(code))

	var digest [32]byte
	copy(digest[:], h.Sum(nil))
	return digest
}

// newCode draws CodeLength digits from crypto/rand.
//
// **crypto/rand and not math/rand**, which is not pedantry here: math/rand is seeded and its
// sequence is reproducible, so anybody who watched a few codes could predict the next one and log in
// as the next person to sign up. rand.Int over a power of ten is uniform - no modulo bias - and the
// %06d keeps a small draw ("1234") six digits wide, since a code of a different length is one the
// user cannot type into a six-box field.
func newCode() (string, error) {
	limit := new(big.Int).Exp(big.NewInt(10), big.NewInt(CodeLength), nil)
	n, err := rand.Int(rand.Reader, limit)
	if err != nil {
		return "", fmt.Errorf("auth: no randomness for a verification code: %w", err)
	}
	return fmt.Sprintf("%0*d", CodeLength, n), nil
}

// CanonicalPhone reduces whatever was typed to the one spelling this flow uses everywhere:
// 998XXXXXXXXX, twelve digits, no plus and no spaces.
//
// **Both endpoints have to call it or the flow breaks silently.** The pending codes are keyed by
// phone number, so a code stored under "998901234567" and looked up under "+998 90 123 45 67" is a
// map miss - and a map miss reads exactly like "you never asked for a code", which is the one error
// message that sends a user round the loop again instead of telling them anything.
//
// It is also what goes into users.phone for every account this flow creates, which is why it is
// strict rather than forgiving: two spellings of one number in a UNIQUE column are two accounts, and
// the second one owns none of the first one's shops.
//
// Deliberately narrow - nine digits, or twelve beginning with 998. A national trunk prefix ("8 90
// ...") is not accepted because it is ambiguous, and the operator code is not checked against a list
// because that list changes without telling us and a rejected real number is worse than a code sent
// into the void.
func CanonicalPhone(raw string) (string, bool) {
	digits := NormalizePhone(raw)

	// "00998..." is the international prefix dialled out loud. no uzbek operator code starts with 0,
	// so this cannot eat a digit of a local number.
	digits = strings.TrimPrefix(digits, "00")

	switch {
	case len(digits) == 9:
		// "901234567" - the form printed on shop signs and typed by everyone
		return "998" + digits, true
	case len(digits) == 12 && strings.HasPrefix(digits, "998"):
		return digits, true
	default:
		return "", false
	}
}

// MaskPhone turns "998901234567" into "9989****4567" for a log line.
//
// A phone number is this system's identity key - it is what an account is looked up by - so a log
// holding one in full hands an account identifier to anyone who can read logs, which in production
// means the hosting provider and whatever collects them. Enough digits survive to match a line
// against a specific user when somebody reports that no code arrived, which is the only reason the
// number is logged at all.
func MaskPhone(phone string) string {
	if len(phone) <= 8 {
		return "***"
	}
	return phone[:4] + strings.Repeat("*", len(phone)-8) + phone[len(phone)-4:]
}

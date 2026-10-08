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
// **the pending codes live in ram and deliberately not in postgres**: a signup abandoned between
// "send me a code" and "here is the code" must leave nothing behind, and a codes table would collect
// a row per abandoned attempt holding a phone number nobody asked us to keep. the cost is that a
// restart invalidates every code in flight.
//
// a mutex and a plain map rather than session.go's sync.Map, and the difference is load-bearing:
// every wrong guess is a read-modify-write on an existing entry, which sync.Map can only do as
// Load-then-Store - so two concurrent guesses would leak an extra try past the attempt cap.

// the numbers that keep this flow from costing money. every send is paid for (CLAUDE.md §3,
// ~150 000 SMS budgeted for the year), so these are correctness, not hardening.
const (
	// what every uzbek service sends and what the sms template is moderated around. only 10^6
	// possibilities, which is why guessing is stopped by MaxCodeAttempts and not by the length.
	CodeLength = 6

	// long enough to walk to the sms app, short enough that a code seen over a shoulder is worthless
	CodeTTL = 5 * time.Minute

	// with 10^6 codes and three tries, a guessing attack needs ~333 000 paid sends per expected hit
	MaxCodeAttempts = 3

	// how long "отправить ещё раз" stays disabled; the app draws it as a countdown
	ResendCooldown = 60 * time.Second

	// the per-phone ceiling underneath the cooldown, which alone would still allow ~1400 paid
	// messages a day at one number. three quick attempts, then one an hour.
	phoneSendBurst  = 3
	phoneSendRate   = 1.0 / 3600.0 // one refill per hour
	phoneSendMemory = 24 * time.Hour

	// **the ceiling on the whole bill, and the only limit an attacker cannot spread around.** the
	// per-phone budget stops one number being made to cost money and the per-ip one stops a single
	// machine walking through numbers, but a thousand numbers hit once each from a thousand
	// addresses passes both. this is far above what the launch cohort sends in a day.
	dailySendBudget = 2000
	dailySendRate   = dailySendBudget / (24 * 60 * 60.0)

	codeSweepInterval = 30 * time.Second
)

// sentinels rather than strings: endpoints.PhoneAuth turns each into its own machine-readable code
var (
	ErrNoPendingCode   = errors.New("auth: no code was requested for this number")
	ErrCodeExpired     = errors.New("auth: the code has expired")
	ErrCodeMismatch    = errors.New("auth: that is not the code we sent")
	ErrTooManyAttempts = errors.New("auth: too many wrong attempts, the code is dead")
	ErrResendTooSoon   = errors.New("auth: a code was sent to this number moments ago")
	ErrSendBudget      = errors.New("auth: too many codes have been sent to this number")
)

// what a code was minted *for*, checked on the way back in. two flows send a code to a phone - the
// login and the phone change - and they share one map because the cooldown and the budget are
// per-number, so this is what stops a code issued for one being spent on the other.
type CodePurpose string

const (
	CodeLogin       CodePurpose = "login"
	CodePhoneChange CodePurpose = "phone_change"
	CodeDeletion    CodePurpose = "deletion"
)

// what a correct code proves: this caller controls this number, and - for a login - the name and
// role they registered with. also what [CodeManager.Issue] takes, so minting and proving share one
// shape and a new field cannot be added to one end without the other seeing it.
type Pending struct {
	Purpose CodePurpose
	Phone   string // canonical, 998XXXXXXXXX

	// both empty on [CodePhoneChange]: the account already exists and neither is being set.
	Name string
	Role string
}

// CodeManager holds every code that has been sent and not yet used.
type CodeManager struct {
	mu      sync.Mutex
	pending map[string]*pendingCode // canonical phone -> the code in flight for it

	// both nil when sends are free - see NewCodeManager
	budget *ratelimit.Limiter // per phone
	daily  *ratelimit.Limiter // every caller together

	// zero unless WithReviewAccount armed it
	review reviewAccount
}

// the one number whose code is a constant we chose rather than one we minted - see
// [CodeManager.WithReviewAccount]
type reviewAccount struct {
	phone string // canonical, 998XXXXXXXXX
	code  string
}

// the single bucket the daily budget lives in: it is a ceiling on the total, not on a caller
const everyone = "all"

type pendingCode struct {
	// **the code itself is never stored** - sha256(salt || code), so a heap dump yields nothing
	// typeable. salted per entry because six digits is a space an unsalted digest reverses instantly.
	salt   [16]byte
	digest [32]byte

	purpose  CodePurpose
	name     string
	role     string
	attempts int
	issuedAt time.Time
}

// NewCodeManager builds the store for the codes in flight. **paidDelivery is the only thing the
// per-phone budget is for**: with the console sender there is no bill to protect, and enforcing it
// would only lock whoever is testing out of their own number for an hour. the cooldown applies
// either way - that one is about not sending a second code to somebody who already has one.
func NewCodeManager(paidDelivery bool) *CodeManager {
	m := &CodeManager{pending: make(map[string]*pendingCode)}
	if paidDelivery {
		m.budget = ratelimit.New(phoneSendRate, phoneSendBurst, phoneSendMemory)
		m.daily = ratelimit.New(dailySendRate, dailySendBudget, 48*time.Hour)
	}

	// without it the map is a slow leak of phone numbers: a user who never types the code leaves an
	// entry nothing else deletes
	go m.sweep(codeSweepInterval, CodeTTL)

	return m
}

// WithReviewAccount arms the single number Google's reviewer signs in with: [code] is handed back
// by Issue instead of a fresh one, and [NeedsDelivery] answers false for it.
//
// **It exists because the login cannot be walked by a reviewer otherwise.** The code is delivered
// through Telegram, and a reviewer in another country has no Telegram account on the number they
// type - so the review stops on the first screen and the listing is refused as broken software.
//
// **It is a login bypass on a known number, so it is armed by configuration and meant to be
// disarmed.** Unset the two variables once the review is over. What it can reach is bounded by what
// a signup can: the role is whatever the app asked for mapped through the customer/shop_owner pair,
// never admin.
//
// Either argument empty leaves the manager unarmed - that is the normal state. Call it at startup
// only: nothing guards the field, because it is read under the lock Issue already holds and written
// before the server accepts a request.
func (m *CodeManager) WithReviewAccount(phone, code string) *CodeManager {
	if phone == "" || code == "" {
		return m
	}
	m.review = reviewAccount{phone: phone, code: code}
	return m
}

// NeedsDelivery reports whether a code minted for this number still has to reach a provider. False
// only for the review account, whose code was published to Google rather than sent to a phone.
func (m *CodeManager) NeedsDelivery(phone string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return !m.isReview(phone)
}

// call under the lock. the empty check is what keeps an unarmed manager from matching the empty
// string, which is not a phone but is what an unset field holds
func (m *CodeManager) isReview(phone string) bool {
	return m.review.phone != "" && phone == m.review.phone
}

// Issue mints a code and remembers its hash. The returned code is the only plaintext copy that ever
// exists, and the caller's one job is to hand it to a verify.Sender.
//
// The second return is what is left on the cooldown, meaningful only alongside ErrResendTooSoon -
// the app draws it as a countdown. Neither the cooldown nor the budget cares what the code is for:
// a phone change costs exactly what a login does.
func (m *CodeManager) Issue(p Pending) (code string, wait time.Duration, err error) {
	code, err = newCode()
	if err != nil {
		return "", 0, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// before the budget, so a user tapping the button twice spends no token
	if existing, live := m.pending[p.Phone]; live {
		if since := time.Since(existing.issuedAt); since < ResendCooldown {
			return "", ResendCooldown - since, ErrResendTooSoon
		}
	}

	// the review account gets the constant the reviewer was given, and neither budget applies to it:
	// both exist to cap a bill, and nothing is sent for this number
	if m.isReview(p.Phone) {
		code = m.review.code
	} else {
		if m.budget != nil && !m.budget.Allow(p.Phone) {
			return "", 0, ErrSendBudget
		}
		if m.daily != nil && !m.daily.Allow(everyone) {
			return "", 0, ErrSendBudget
		}
	}

	entry := &pendingCode{purpose: p.Purpose, name: p.Name, role: p.Role, issuedAt: time.Now()}
	if _, err := rand.Read(entry.salt[:]); err != nil {
		return "", 0, fmt.Errorf("auth: no randomness for a code salt: %w", err)
	}
	entry.digest = hashCode(entry.salt, code)

	// a new code replaces the old outright, attempts and all: two live codes for one number would
	// double the chance of a blind guess
	m.pending[p.Phone] = entry

	return code, 0, nil
}

// Verify checks a typed code and hands back what it was proving. One code, one login: the entry is
// consumed either way, so a correct code cannot be replayed and a dead one cannot be guessed at.
//
// [purpose] must match what the code was minted for. **A mismatch leaves the entry alive** - the
// code belongs to the other flow, and burning it here would break the user who is actually in it.
func (m *CodeManager) Verify(purpose CodePurpose, phone, code string) (Pending, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	entry, live := m.pending[phone]
	if !live || entry.purpose != purpose {
		return Pending{}, ErrNoPendingCode
	}

	// as well as in the sweeper, which runs on a timer: between two passes an expired entry is still
	// in the map
	if time.Since(entry.issuedAt) > CodeTTL {
		delete(m.pending, phone)
		return Pending{}, ErrCodeExpired
	}

	// constant time: digests do not leak the way plaintext would, but it is the habit that matters
	// the day something longer than a hash is compared here
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
	return Pending{Purpose: entry.purpose, Phone: phone, Name: entry.name, Role: entry.role}, nil
}

// Drop forgets a pending code, for the one caller that needs it: the endpoint, when the provider
// refused to deliver. **the budget token stays spent** - a refused send may still have been billed.
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

// **crypto/rand and not math/rand**: math/rand is seeded and reproducible, so anybody who watched a
// few codes could predict the next one and log in as the next person to sign up. rand.Int over a
// power of ten is uniform, and the zero-padding keeps a small draw six digits wide.
func newCode() (string, error) {
	limit := new(big.Int).Exp(big.NewInt(10), big.NewInt(CodeLength), nil)
	n, err := rand.Int(rand.Reader, limit)
	if err != nil {
		return "", fmt.Errorf("auth: no randomness for a verification code: %w", err)
	}
	return fmt.Sprintf("%0*d", CodeLength, n), nil
}

// CanonicalPhone reduces whatever was typed to the one spelling used everywhere: 998XXXXXXXXX,
// twelve digits, no plus, no spaces.
//
// **every endpoint has to call it or the flow breaks silently**: the pending codes are keyed by this
// string, and it is also what goes into users.phone - where two spellings of one number in a UNIQUE
// column are two accounts, the second owning none of the first's shops.
//
// deliberately narrow. the operator code is not checked against a list: that list changes without
// telling us, and a rejected real number is worse than a code sent into the void.
func CanonicalPhone(raw string) (string, bool) {
	digits := digitsOf(raw)

	// the international prefix dialled out loud. no uzbek operator code starts with 0, so this
	// cannot eat a digit of a local number.
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

// digitsOf drops everything that is not a digit, so "+998 90 123 45 67" and "998901234567" are the
// same string by the time anything compares them.
func digitsOf(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	return digits.String()
}

// MaskPhone turns "998901234567" into "9989****4567". a phone number is this system's identity key,
// so a log holding one in full hands an account identifier to anyone who can read logs. enough
// digits survive to match a line against a user who reports that no code arrived.
func MaskPhone(phone string) string {
	if len(phone) <= 8 {
		return "***"
	}
	return phone[:4] + strings.Repeat("*", len(phone)-8) + phone[len(phone)-4:]
}

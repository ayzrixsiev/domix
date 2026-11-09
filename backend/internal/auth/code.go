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

// the one-time code login: a code is delivered to a typed number, and typing it back mints a jwt.
//
// **the pending codes live in ram and deliberately not in postgres**: a signup abandoned halfway must
// leave no row holding a phone number nobody asked us to keep. the cost is that a restart invalidates
// every code in flight.
//
// a mutex and a plain map rather than sync.Map: every wrong guess is a read-modify-write, which
// sync.Map can only do as Load-then-Store, so two concurrent guesses would leak a try past the cap.

// every send is paid for, so these numbers are correctness rather than hardening
const (
	// only 10^6 possibilities, which is why guessing is stopped by MaxCodeAttempts and not by the length
	CodeLength = 6

	// long enough to walk to the sms app, short enough that a code seen over a shoulder is worthless
	CodeTTL = 5 * time.Minute

	// with 10^6 codes and three tries, a guessing attack needs ~333 000 paid sends per expected hit
	MaxCodeAttempts = 3

	// how long "отправить ещё раз" stays disabled; the app draws it as a countdown
	ResendCooldown = 60 * time.Second

	// the ceiling underneath the cooldown, which alone would allow ~1400 paid messages a day at one number
	phoneSendBurst  = 3
	phoneSendRate   = 1.0 / 3600.0 // one refill per hour
	phoneSendMemory = 24 * time.Hour

	// **the ceiling on the whole bill, and the only limit an attacker cannot spread around**: a thousand
	// numbers hit once each from a thousand addresses passes both of the others.
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

// what a code was minted *for*. the login and the deletion page share one map, because the cooldown and
// the budget are per-number, so this is what stops a code issued for one being spent on the other.
type CodePurpose string

const (
	CodeLogin    CodePurpose = "login"
	CodeDeletion CodePurpose = "deletion"
)

// what a correct code proves, and what Issue takes: minting and proving share one shape, so a new field
// cannot be added to one end without the other seeing it.
type Pending struct {
	Purpose CodePurpose
	Phone   string // canonical, 998XXXXXXXXX

	// both empty on [CodeDeletion]: the account already exists and neither is being set.
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

// the one number whose code is a constant we chose - see [CodeManager.WithReviewAccount]
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

// NewCodeManager builds the store for the codes in flight. **paidDelivery is the only thing the per-phone
// budget is for**: with the console sender there is no bill to protect. the cooldown applies either way.
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

// WithReviewAccount arms the single number Google's reviewer signs in with: [code] is handed back by
// Issue instead of a fresh one, and [NeedsDelivery] answers false for it. Without it the review stops on
// the login screen, since the code goes to a Telegram account the reviewer does not have.
//
// **it is a login bypass on a known number, so unset the two variables once the review is over.** what
// it can reach is bounded by what a signup can: never admin. Call it at startup only, before the server
// accepts a request.
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

// call under the lock. the empty check keeps an unarmed manager from matching the empty string
func (m *CodeManager) isReview(phone string) bool {
	return m.review.phone != "" && phone == m.review.phone
}

// Issue mints a code and remembers its hash. The returned code is the only plaintext copy that ever
// exists. The second return is what is left on the cooldown, meaningful only alongside ErrResendTooSoon;
// neither cooldown nor budget cares what the code is for.
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

	// neither budget applies to the review account: both exist to cap a bill, and nothing is sent for it
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

	// a new code replaces the old outright, attempts and all: two live codes double a blind guess's chance
	m.pending[p.Phone] = entry

	return code, 0, nil
}

// Verify checks a typed code and hands back what it was proving. One code, one login: the entry is
// consumed either way. **a purpose mismatch leaves the entry alive** - the code belongs to the other
// flow, and burning it here would break the user who is actually in it.
func (m *CodeManager) Verify(purpose CodePurpose, phone, code string) (Pending, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	entry, live := m.pending[phone]
	if !live || entry.purpose != purpose {
		return Pending{}, ErrNoPendingCode
	}

	// the sweeper runs on a timer, so between two passes an expired entry is still in the map
	if time.Since(entry.issuedAt) > CodeTTL {
		delete(m.pending, phone)
		return Pending{}, ErrCodeExpired
	}

	// constant time: the habit that matters the day something longer than a hash is compared here
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

// **crypto/rand and not math/rand**: math/rand is seeded and reproducible, so anybody who watched a few
// codes could predict the next one. the zero-padding keeps a small draw six digits wide.
func newCode() (string, error) {
	limit := new(big.Int).Exp(big.NewInt(10), big.NewInt(CodeLength), nil)
	n, err := rand.Int(rand.Reader, limit)
	if err != nil {
		return "", fmt.Errorf("auth: no randomness for a verification code: %w", err)
	}
	return fmt.Sprintf("%0*d", CodeLength, n), nil
}

// CanonicalPhone reduces whatever was typed to the one spelling used everywhere: 998XXXXXXXXX.
//
// **every endpoint has to call it or the flow breaks silently**: pending codes are keyed by this string
// and it is what goes into users.phone, where two spellings in a UNIQUE column are two accounts.
//
// the operator code is deliberately not checked against a list: that list changes without telling us.
func CanonicalPhone(raw string) (string, bool) {
	digits := digitsOf(raw)

	// no uzbek operator code starts with 0, so this cannot eat a digit of a local number
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

func digitsOf(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	return digits.String()
}

// MaskPhone turns "998901234567" into "9989****4567": a phone number is this system's identity key, so a
// log holding one in full hands an account identifier to anyone who can read logs.
func MaskPhone(phone string) string {
	if len(phone) <= 8 {
		return "***"
	}
	return phone[:4] + strings.Repeat("*", len(phone)-8) + phone[len(phone)-4:]
}

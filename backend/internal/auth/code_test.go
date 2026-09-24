package auth

import (
	"errors"
	"fmt"
	"testing"
	"time"
)

// The code login's rules, pinned. Every one of these is a rule that costs money or hands out a
// token when it is wrong, and none of them is visible from the outside: a broken attempt cap and a
// working one look identical until somebody is brute-forcing the endpoint.

// CanonicalPhone is the single spelling everything else is keyed by - the pending code map, and
// users.phone for every account this flow creates. Two spellings of one number is a map miss on the
// way in (reported to the user as "you never asked for a code") and a duplicate account on the way
// out, on a row that owns none of the original's shops.
func TestCanonicalPhone(t *testing.T) {
	cases := []struct {
		name  string
		typed string
		want  string
		ok    bool
	}{
		{"as everyone types it", "901234567", "998901234567", true},
		{"already canonical", "998901234567", "998901234567", true},
		{"as it is printed on a shop sign", "+998 90 123 45 67", "998901234567", true},
		{"dialled internationally", "00998901234567", "998901234567", true},
		{"with the punctuation a keyboard offers", "(90) 123-45-67", "998901234567", true},

		{"nothing at all", "", "", false},
		{"a few digits", "12345", "", false},
		{"a russian number", "79161234567", "", false},
		{"a ukrainian number, right length wrong country", "380501234567", "", false},
		// ambiguous: "8" could be a trunk prefix or an operator code, and guessing wrong sends a paid
		// message to a stranger
		{"a national trunk prefix", "8901234567", "", false},
		{"one digit too many", "9989012345678", "", false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := CanonicalPhone(c.typed)
			if ok != c.ok {
				t.Fatalf("CanonicalPhone(%q) accepted=%v, want %v", c.typed, ok, c.ok)
			}
			if got != c.want {
				t.Fatalf("CanonicalPhone(%q) = %q, want %q", c.typed, got, c.want)
			}
		})
	}
}

const testPhone = "998901234567"

// issueFor mints a code and hands back the plaintext, failing the test if the manager refuses.
func issueFor(t *testing.T, m *CodeManager, phone string) string {
	t.Helper()

	code, _, err := m.Issue(Pending{Purpose: CodeLogin, Phone: phone, Name: "Тест", Role: "customer"})
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	return code
}

// backdate ages a pending entry, which is how expiry and the resend cooldown are tested without a
// test that sleeps for five minutes. Reaching into the struct rather than injecting a clock: the
// test lives in this package, and a clock field on CodeManager would be production code shaped
// around a test.
func backdate(t *testing.T, m *CodeManager, phone string, by time.Duration) {
	t.Helper()

	m.mu.Lock()
	defer m.mu.Unlock()

	entry, live := m.pending[phone]
	if !live {
		t.Fatalf("no pending code for %s to backdate", phone)
	}
	entry.issuedAt = entry.issuedAt.Add(-by)
}

// wrongCode is the sent code with its last digit moved on by one - a realistic mistype rather than
// a string that could never be produced by newCode.
func wrongCode(sent string) string {
	last := sent[len(sent)-1]
	if last == '9' {
		last = '0'
	} else {
		last++
	}
	return sent[:len(sent)-1] + string(last)
}

func TestVerifyingACode(t *testing.T) {
	cases := []struct {
		name string
		// typed decides what goes into Verify, and may age the entry first
		typed func(t *testing.T, m *CodeManager, sent string) string
		want  error
	}{
		{
			name:  "the code we sent",
			typed: func(_ *testing.T, _ *CodeManager, sent string) string { return sent },
			want:  nil,
		},
		{
			name:  "one digit off",
			typed: func(_ *testing.T, _ *CodeManager, sent string) string { return wrongCode(sent) },
			want:  ErrCodeMismatch,
		},
		{
			name:  "nothing typed at all",
			typed: func(_ *testing.T, _ *CodeManager, _ string) string { return "" },
			want:  ErrCodeMismatch,
		},
		{
			// the right code, arriving a minute after it died. the sweeper runs on a timer, so Verify
			// has to notice this itself or a code stays usable until the next sweep
			name: "the right code, too late",
			typed: func(t *testing.T, m *CodeManager, sent string) string {
				backdate(t, m, testPhone, CodeTTL+time.Minute)
				return sent
			},
			want: ErrCodeExpired,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m := NewCodeManager(true)
			sent := issueFor(t, m, testPhone)

			pending, err := m.Verify(CodeLogin, testPhone, c.typed(t, m, sent))
			if !errors.Is(err, c.want) {
				t.Fatalf("Verify returned %v, want %v", err, c.want)
			}
			if c.want != nil {
				return
			}

			// what a correct code proves travels back with it: the name and role typed on the phone
			// screen, which is the only place they were ever collected
			if pending.Phone != testPhone || pending.Name != "Тест" || pending.Role != "customer" {
				t.Fatalf("a correct code returned %+v", pending)
			}
		})
	}
}

// Two flows send codes to phones - signing in, and moving an existing account onto a new number -
// and they share one pending map because the cooldown and the budget are per-number. The purpose is
// what keeps them from spending each other's codes: a login code typed into the phone-change
// endpoint has to read as "no code was requested", and the entry has to survive it, or the flow
// that *is* waiting on that code would be broken by the one that is not.
func TestACodeCannotBeSpentOnTheWrongFlow(t *testing.T) {
	m := NewCodeManager(true)
	sent := issueFor(t, m, testPhone) // a login code

	if _, err := m.Verify(CodePhoneChange, testPhone, sent); !errors.Is(err, ErrNoPendingCode) {
		t.Fatalf("a login code verified as a phone change: %v", err)
	}

	// untouched, attempts included: the wrong flow asking must not cost the right one a guess
	pending, err := m.Verify(CodeLogin, testPhone, sent)
	if err != nil {
		t.Fatalf("the login code stopped working after the wrong flow asked for it: %v", err)
	}
	if pending.Purpose != CodeLogin {
		t.Fatalf("a correct code came back as %+v", pending)
	}
}

// A number nobody has asked for a code for. Distinct from a wrong code on purpose - the app sends
// the user back to the phone screen for this one instead of leaving them typing into a keypad that
// will never accept anything.
func TestVerifyingWithoutHavingAskedForACode(t *testing.T) {
	m := NewCodeManager(true)

	if _, err := m.Verify(CodeLogin, testPhone, "123456"); !errors.Is(err, ErrNoPendingCode) {
		t.Fatalf("Verify against an empty manager returned %v, want ErrNoPendingCode", err)
	}
}

// One code, one login. Without the entry being consumed, a code intercepted once would keep working
// for its whole five minutes, on as many devices as wanted.
func TestACorrectCodeCannotBeUsedTwice(t *testing.T) {
	m := NewCodeManager(true)
	sent := issueFor(t, m, testPhone)

	if _, err := m.Verify(CodeLogin, testPhone, sent); err != nil {
		t.Fatalf("the first use of a correct code failed: %v", err)
	}
	if _, err := m.Verify(CodeLogin, testPhone, sent); !errors.Is(err, ErrNoPendingCode) {
		t.Fatalf("the second use returned %v, want ErrNoPendingCode", err)
	}
}

// **The one test standing between this endpoint and a brute-force.** Six digits is a million
// possibilities; without a cap, a script guessing at the rate limiter's pace walks through them.
// Three tries and the entry dies, so an attacker has to pay for a new sms every three guesses.
func TestThreeWrongGuessesKillTheCode(t *testing.T) {
	m := NewCodeManager(true)
	sent := issueFor(t, m, testPhone)
	wrong := wrongCode(sent)

	for attempt := 1; attempt < MaxCodeAttempts; attempt++ {
		if _, err := m.Verify(CodeLogin, testPhone, wrong); !errors.Is(err, ErrCodeMismatch) {
			t.Fatalf("guess %d returned %v, want ErrCodeMismatch", attempt, err)
		}
	}

	if _, err := m.Verify(CodeLogin, testPhone, wrong); !errors.Is(err, ErrTooManyAttempts) {
		t.Fatalf("guess %d returned %v, want ErrTooManyAttempts", MaxCodeAttempts, err)
	}

	// and the entry is gone, so the code that *was* correct is worthless too - otherwise an attacker
	// who exhausted the cap could simply carry on where they left off
	if _, err := m.Verify(CodeLogin, testPhone, sent); !errors.Is(err, ErrNoPendingCode) {
		t.Fatalf("the real code still worked after the cap: %v", err)
	}
}

// The cooldown is the first half of the per-phone send limit, and the wait it returns is what the
// app draws as a countdown. A zero there is an app that retries immediately.
func TestResendingIsHeldOffForAMinute(t *testing.T) {
	m := NewCodeManager(true)
	issueFor(t, m, testPhone)

	_, wait, err := m.Issue(Pending{Purpose: CodeLogin, Phone: testPhone, Name: "Тест", Role: "customer"})
	if !errors.Is(err, ErrResendTooSoon) {
		t.Fatalf("an immediate resend returned %v, want ErrResendTooSoon", err)
	}
	if wait <= 0 || wait > ResendCooldown {
		t.Fatalf("the countdown is %v, want something inside (0, %v]", wait, ResendCooldown)
	}

	// once the cooldown has passed, a new code replaces the old one outright
	backdate(t, m, testPhone, ResendCooldown+time.Second)

	second := issueFor(t, m, testPhone)
	if _, err := m.Verify(CodeLogin, testPhone, second); err != nil {
		t.Fatalf("the re-sent code did not verify: %v", err)
	}
}

// The second half of the per-phone limit. The cooldown alone only makes an attacker wait a minute
// between sends - still around 1400 paid messages a day aimed at one number - so the budget caps
// how many a single number can ever cost us.
func TestOneNumberCannotBeMadeToCostForever(t *testing.T) {
	m := NewCodeManager(true)

	for sent := 0; sent < phoneSendBurst; sent++ {
		issueFor(t, m, testPhone)
		// step past the cooldown, so this is the budget being tested and not the cooldown again
		backdate(t, m, testPhone, ResendCooldown+time.Second)
	}

	if _, _, err := m.Issue(Pending{Purpose: CodeLogin, Phone: testPhone, Name: "Тест", Role: "customer"}); !errors.Is(err, ErrSendBudget) {
		t.Fatalf("send %d returned %v, want ErrSendBudget", phoneSendBurst+1, err)
	}

	// and it is per number: a different phone is unaffected
	if _, _, err := m.Issue(Pending{Purpose: CodeLogin, Phone: "998901234568", Name: "Тест", Role: "customer"}); err != nil {
		t.Fatalf("a different number was refused too: %v", err)
	}
}

// The budget guards the sms bill, so where there is no bill there is nothing to guard - and the
// cost of arming it anyway is real: the console sender prints codes into the log, and a developer
// testing the login screen would spend the five sends in a couple of minutes and then be refused on
// their own number for an hour, by a limiter only a restart clears.
func TestFreeDeliveryHasNoSendCeiling(t *testing.T) {
	m := NewCodeManager(false)

	// well past the paid ceiling, so this fails the moment the budget is armed when it should not be
	issueFor(t, m, testPhone)
	for sent := 1; sent < phoneSendBurst*3; sent++ {
		// stepping past the cooldown first, so what is being tested here is the ceiling and not it
		backdate(t, m, testPhone, ResendCooldown+time.Second)
		issueFor(t, m, testPhone)
	}

	// the cooldown is not part of the deal, though: it is about not sending a second code to somebody
	// who already has one, which is true whoever is paying
	if _, wait, err := m.Issue(Pending{Purpose: CodeLogin, Phone: testPhone, Name: "Тест", Role: "customer"}); !errors.Is(err, ErrResendTooSoon) || wait <= 0 {
		t.Fatalf("an immediate resend returned (%v, %v), want ErrResendTooSoon with a countdown", wait, err)
	}
}

// The code has to be typeable into a six-box field, and it has to be unpredictable. A leading zero
// is the case a naive %d drops, turning a six-digit code into five.
func TestCodesAreSixDigitsAndNotGuessable(t *testing.T) {
	seen := make(map[string]bool)

	for i := 0; i < 200; i++ {
		code, err := newCode()
		if err != nil {
			t.Fatalf("newCode: %v", err)
		}
		if len(code) != CodeLength {
			t.Fatalf("code %q is %d characters, want %d", code, len(code), CodeLength)
		}
		for _, r := range code {
			if r < '0' || r > '9' {
				t.Fatalf("code %q is not all digits", code)
			}
		}
		seen[code] = true
	}

	// 200 draws from a million: a collision is possible (~2% of runs), a *pile* of them is a broken
	// source of randomness. anything below 195 distinct means the draw is not uniform.
	if len(seen) < 195 {
		t.Fatalf("200 codes produced only %d distinct values", len(seen))
	}
}

// The plaintext must not be recoverable from the manager: a heap dump or a debugger on this process
// must not yield something that can be typed into the verify endpoint.
func TestThePlaintextCodeIsNeverKept(t *testing.T) {
	m := NewCodeManager(true)
	sent := issueFor(t, m, testPhone)

	m.mu.Lock()
	defer m.mu.Unlock()

	entry := m.pending[testPhone]
	if entry.digest != hashCode(entry.salt, sent) {
		t.Fatal("the stored digest is not the hash of the code that was sent")
	}
	// the salt is what makes the digest useless to an attacker who dumps it: six digits is a 10^6
	// space, so an unsalted sha256 would be reversed by brute force in milliseconds
	if entry.salt == [16]byte{} {
		t.Fatal("the entry has no salt")
	}
}

func TestMaskPhone(t *testing.T) {
	cases := map[string]string{
		"998901234567": "9989****4567",
		"12345678":     "***",
		"":             "***",
	}

	for phone, want := range cases {
		if got := MaskPhone(phone); got != want {
			t.Errorf("MaskPhone(%q) = %q, want %q", phone, got, want)
		}
	}
}

// **the ceiling on the bill, and the only limit an attacker cannot spread around.** The per-phone
// budget stops one number being made to cost money and the per-address one stops a single machine
// walking through numbers - but a thousand numbers hit once each from a thousand addresses passes
// both of those and bills us for a thousand messages.
func TestTheDailyBudgetCapsWhatEverybodyTogetherCanSpend(t *testing.T) {
	codes := NewCodeManager(true)

	// a different number every time, so nothing here is refused by the per-phone budget
	sent := 0
	for i := range dailySendBudget + 50 {
		phone := fmt.Sprintf("9989%08d", i)
		if _, _, err := codes.Issue(Pending{Purpose: CodeLogin, Phone: phone}); err == nil {
			sent++
			continue
		}
		break
	}

	if sent > dailySendBudget {
		t.Fatalf("%d codes were minted, want at most the daily budget of %d", sent, dailySendBudget)
	}
	if sent < dailySendBudget {
		t.Fatalf("the budget ran out after %d codes, want the full %d", sent, dailySendBudget)
	}
}

// With the console sender there is no bill to protect, and enforcing a budget would only lock
// whoever is testing out of their own number - from a limiter that only a restart clears.
func TestNoBudgetIsEnforcedWhenSendingIsFree(t *testing.T) {
	codes := NewCodeManager(false)

	for i := range phoneSendBurst + 3 {
		phone := fmt.Sprintf("9989%08d", i)
		if _, _, err := codes.Issue(Pending{Purpose: CodeLogin, Phone: phone}); err != nil {
			t.Fatalf("the console sender was budgeted after %d codes: %v", i, err)
		}
	}
}

package verify

import (
	"context"
	"testing"
)

// Which provider gets picked, and when the api refuses to boot instead.
//
// **Nothing here talks to a network.** New only builds a struct - the first byte leaves this process
// inside Send - so the whole selection table runs offline, which is the point of keeping the choice
// in a pure function rather than inline in main.go.

func TestChoosingAProvider(t *testing.T) {
	const (
		token    = "gateway-token"
		email    = "sales@domix.uz"
		password = "not-a-real-password"
		template = "Domix: {code} - tasdiqlash kodi"
	)

	cases := []struct {
		name     string
		settings Settings
		want     string // the kind New should report, "" when it should refuse
	}{
		{
			// the founder's laptop, and every machine that is not production: an empty .env still
			// has a working login, printed into the log
			name:     "nothing configured at all",
			settings: Settings{},
			want:     KindConsole,
		},
		{
			name:     "a gateway token",
			settings: Settings{TelegramToken: token},
			want:     KindTelegram,
		},
		{
			name:     "eskiz, fully configured",
			settings: Settings{EskizEmail: email, EskizPassword: password, EskizTemplate: template},
			want:     KindEskiz,
		},
		{
			// telegram is the primary provider (cheaper per message), so it wins when both are
			// present and VERIFY_SENDER is what overrides that
			name:     "both configured",
			settings: Settings{TelegramToken: token, EskizEmail: email, EskizPassword: password, EskizTemplate: template},
			want:     KindTelegram,
		},
		{
			name:     "both configured, eskiz named explicitly",
			settings: Settings{Sender: KindEskiz, TelegramToken: token, EskizEmail: email, EskizPassword: password, EskizTemplate: template},
			want:     KindEskiz,
		},
		{
			// a .env is typed by a person, so the name is matched loosely
			name:     "named with capitals and whitespace",
			settings: Settings{Sender: "  Telegram ", TelegramToken: token},
			want:     KindTelegram,
		},
		{
			// console on purpose, with real credentials sitting right there: the way to test the
			// flow end to end without spending money
			name:     "console named explicitly while eskiz is configured",
			settings: Settings{Sender: KindConsole, EskizEmail: email, EskizPassword: password, EskizTemplate: template},
			want:     KindConsole,
		},

		// every refusal below is a .env somebody is halfway through filling in. the alternative -
		// quietly falling back to the console - is an api that boots green, answers 200 to every
		// login and delivers nothing, found by the first real user rather than at startup.
		{
			name:     "eskiz with no password",
			settings: Settings{EskizEmail: email},
			want:     "",
		},
		{
			name:     "eskiz with no password, named explicitly",
			settings: Settings{Sender: KindEskiz, EskizEmail: email},
			want:     "",
		},
		{
			// the text has to be one Eskiz already moderated, so there is nothing sane to default to
			name:     "eskiz with no message template",
			settings: Settings{EskizEmail: email, EskizPassword: password},
			want:     "",
		},
		{
			// would send a perfectly valid sms carrying no code at all
			name:     "an eskiz template with no placeholder",
			settings: Settings{EskizEmail: email, EskizPassword: password, EskizTemplate: "Domix kodi"},
			want:     "",
		},
		{
			name:     "telegram named with no token",
			settings: Settings{Sender: KindTelegram},
			want:     "",
		},
		{
			name:     "a provider we have never heard of",
			settings: Settings{Sender: "twilio"},
			want:     "",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			sender, kind, err := New(c.settings)

			if c.want == "" {
				if err == nil {
					t.Fatalf("New accepted a broken configuration and chose %q", kind)
				}
				if sender != nil {
					t.Fatal("New returned both an error and a sender")
				}
				return
			}

			if err != nil {
				t.Fatalf("New refused a valid configuration: %v", err)
			}
			if kind != c.want {
				t.Fatalf("New chose %q, want %q", kind, c.want)
			}
			if sender == nil {
				t.Fatal("New reported a provider but returned no sender")
			}
		})
	}
}

// The short number is optional - almost every Eskiz account sends from the shared 4546 - so it has a
// default where the message text deliberately does not.
func TestEskizFallsBackToTheSharedShortNumber(t *testing.T) {
	sender, _, err := New(Settings{
		EskizEmail:    "sales@domix.uz",
		EskizPassword: "not-a-real-password",
		EskizTemplate: "Domix: {code}",
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	if got := sender.(*eskiz).from; got != eskizDefaultFrom {
		t.Fatalf("eskiz sends from %q, want the default %q", got, eskizDefaultFrom)
	}
}

func TestSettingsComeFromTheEnvironment(t *testing.T) {
	t.Setenv(EnvSender, "eskiz")
	t.Setenv(EnvTelegramToken, " gateway-token ") // trimmed: a .env line can carry trailing spaces
	t.Setenv(EnvEskizEmail, "sales@domix.uz")
	t.Setenv(EnvEskizPassword, "not-a-real-password")
	t.Setenv(EnvEskizFrom, "3700")
	t.Setenv(EnvEskizTemplate, "Domix: {code}")

	want := Settings{
		Sender:        "eskiz",
		TelegramToken: "gateway-token",
		EskizEmail:    "sales@domix.uz",
		EskizPassword: "not-a-real-password",
		EskizFrom:     "3700",
		EskizTemplate: "Domix: {code}",
	}
	if got := SettingsFromEnv(); got != want {
		t.Fatalf("SettingsFromEnv() = %+v, want %+v", got, want)
	}
}

// The development provider has to be a real Sender, not a panic waiting for the first login: the
// whole flutter flow is walked against it before there is a gateway balance or a moderated template.
func TestTheConsoleSenderAlwaysSucceeds(t *testing.T) {
	sender, kind, err := New(Settings{})
	if err != nil || kind != KindConsole {
		t.Fatalf("New(Settings{}) = %q, %v", kind, err)
	}

	if err := sender.Send(context.Background(), "998901234567", "123456"); err != nil {
		t.Fatalf("the console sender failed: %v", err)
	}
}

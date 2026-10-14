package verify

import (
	"context"
	"testing"
)

// Which provider gets picked, and when the api refuses to boot instead.
//
// **Nothing here talks to a network**: New only builds a struct, which is the point of keeping the
// choice in a pure function rather than inline in main.go.

func TestChoosingAProvider(t *testing.T) {
	const token = "gateway-token"

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
			// a .env is typed by a person, so the name is matched loosely
			name:     "named with capitals and whitespace",
			settings: Settings{Sender: "  Telegram ", TelegramToken: token},
			want:     KindTelegram,
		},
		{
			// console on purpose, with a real token sitting right there: the way to walk the flow
			// end to end without spending money
			name:     "console named explicitly while a token is configured",
			settings: Settings{Sender: KindConsole, TelegramToken: token},
			want:     KindConsole,
		},
		{
			// a .env somebody is halfway through. the alternative - quietly falling back to the
			// console - is an api that boots green, answers 200 to every login and delivers nothing.
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

func TestSettingsComeFromTheEnvironment(t *testing.T) {
	t.Setenv(EnvSender, "telegram")
	t.Setenv(EnvTelegramToken, " gateway-token ") // trimmed: a .env line can carry trailing spaces

	want := Settings{Sender: "telegram", TelegramToken: "gateway-token"}
	if got := SettingsFromEnv(); got != want {
		t.Fatalf("SettingsFromEnv() = %+v, want %+v", got, want)
	}
}

// The development provider has to be a real Sender, not a panic waiting for the first login: the
// whole flutter flow is walked against it before there is a gateway balance.
func TestTheConsoleSenderAlwaysSucceeds(t *testing.T) {
	sender, kind, err := New(Settings{})
	if err != nil || kind != KindConsole {
		t.Fatalf("New(Settings{}) = %q, %v", kind, err)
	}

	if err := sender.Send(context.Background(), "998901234567", "123456"); err != nil {
		t.Fatalf("the console sender failed: %v", err)
	}
}

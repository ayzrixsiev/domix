// package verify delivers a one-time code to a phone number, and hides which company did it.
//
// **One interface with one method, because that is the entire contract.** The provider is the part
// of this flow most likely to change - Telegram Gateway is cheaper per message but only reaches
// numbers that have Telegram, Eskiz reaches every sim in the country and bills for it, and which of
// those is right is a question about price lists rather than about code. A seam this narrow means
// switching costs one line in main.go, and nothing in internal/auth or internal/endpoints knows a
// provider exists at all.
//
// Nothing here generates, stores or checks a code: that is internal/auth's CodeManager. This package
// only carries a string to a phone.
package verify

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"domix/backend/internal/auth"
)

// Sender delivers one code to one number.
//
// phone arrives canonical - 998XXXXXXXXX, twelve digits, no plus (auth.CanonicalPhone) - and each
// implementation spells it the way its own api wants, because that is exactly the kind of detail
// that should not leak past this boundary.
type Sender interface {
	Send(ctx context.Context, phone, code string) error
}

// the three implementations, named. New returns one of these alongside the sender so main.go can
// say in its startup log which one is live - the single most useful line when codes are not
// arriving.
const (
	KindConsole  = "console"
	KindTelegram = "telegram"
	KindEskiz    = "eskiz"
)

// the environment variables main.go decides on.
const (
	// optional override: name a provider explicitly. Without it the choice follows whichever
	// credentials are present, which is what makes a laptop with an empty .env work out of the box.
	EnvSender = "VERIFY_SENDER"

	// Telegram Gateway (core.telegram.org/gateway/api) - one bearer token from gateway.telegram.org.
	EnvTelegramToken = "TELEGRAM_GATEWAY_TOKEN"

	// Eskiz (notify.eskiz.uz) - a dashboard login, the short number messages are sent from, and the
	// exact moderated text. See eskiz.go for why the text is a required setting rather than a
	// default.
	EnvEskizEmail    = "ESKIZ_EMAIL"
	EnvEskizPassword = "ESKIZ_PASSWORD"
	EnvEskizFrom     = "ESKIZ_FROM"
	EnvEskizTemplate = "ESKIZ_TEMPLATE"
)

// how long one delivery attempt may take. Above any working link to Tashkent or to Telegram, and
// well below the patience of somebody staring at a spinner.
const sendTimeout = 10 * time.Second

// Settings is what the environment says about sending codes. It is a struct rather than a pile of
// os.Getenv calls inside New so the choice can be tested as a table - the selection logic is the
// part that decides whether real money gets spent, and it should not need a .env to exercise.
type Settings struct {
	Sender string // EnvSender, empty means "decide from the credentials below"

	TelegramToken string

	EskizEmail    string
	EskizPassword string
	EskizFrom     string
	EskizTemplate string
}

func SettingsFromEnv() Settings {
	return Settings{
		Sender:        env(EnvSender),
		TelegramToken: env(EnvTelegramToken),
		EskizEmail:    env(EnvEskizEmail),
		EskizPassword: env(EnvEskizPassword),
		EskizFrom:     env(EnvEskizFrom),
		EskizTemplate: env(EnvEskizTemplate),
	}
}

func env(key string) string { return strings.TrimSpace(os.Getenv(key)) }

// New picks an implementation and reports which one by name.
//
// **A half-filled configuration is an error, never a quiet fall back to the console.** Three of the
// four Eskiz settings is somebody midway through a .env, and answering that by printing codes into
// the server log produces an api that boots green, returns 200 to every login attempt and delivers
// nothing at all - discovered by the first real user rather than at startup. The same argument as
// imagestore.R2ConfigFromEnv, for the same reason.
func New(s Settings) (Sender, string, error) {
	kind := strings.ToLower(strings.TrimSpace(s.Sender))
	if kind == "" {
		switch {
		case s.TelegramToken != "":
			kind = KindTelegram
		case s.EskizEmail != "" || s.EskizPassword != "":
			kind = KindEskiz
		default:
			kind = KindConsole
		}
	}

	// one client for all of them, so every send reuses a warm tls connection instead of paying a
	// handshake to Tashkent or to Telegram - the server-side twin of the app's shared http client.
	client := &http.Client{Timeout: sendTimeout}

	switch kind {
	case KindConsole:
		return &consoleSender{}, KindConsole, nil

	case KindTelegram:
		if s.TelegramToken == "" {
			return nil, "", fmt.Errorf("verify: %s=telegram but %s is empty", EnvSender, EnvTelegramToken)
		}
		return &telegramGateway{token: s.TelegramToken, client: client}, KindTelegram, nil

	case KindEskiz:
		sender, err := newEskiz(s, client)
		if err != nil {
			return nil, "", err
		}
		return sender, KindEskiz, nil

	default:
		return nil, "", fmt.Errorf("verify: %s=%q is not one of %q, %q, %q",
			EnvSender, s.Sender, KindConsole, KindTelegram, KindEskiz)
	}
}

// errRefused is what every provider's "your message was not accepted" collapses to. The endpoint
// treats them all the same - drop the pending code, tell the app to try again - so the distinction
// lives in the log line, not in the type.
var errRefused = errors.New("verify: the provider refused the message")

// consoleSender prints the code instead of delivering it.
//
// **It is not a stub, it is the development provider.** The whole login flow - phone screen, code
// screen, jwt, profile - can be walked end to end on a laptop with an empty .env, with no gateway
// account, no Eskiz contract and no moderated template, which is what keeps the flutter side
// unblocked while the paperwork happens. It is also the only sender under which the api can be run
// by somebody who is not the founder.
//
// It shouts on every send rather than only at startup: a server that has been up for a week and is
// silently printing everybody's login codes into its log must be impossible to miss.
type consoleSender struct{}

func (c *consoleSender) Send(_ context.Context, phone, code string) error {
	log.Printf("VERIFY CODE (NOT DELIVERED - console sender) %s -> %s", auth.MaskPhone(phone), code)
	return nil
}

// package verify delivers a one-time code to a phone number.
//
// **one interface with one method, because that is the entire contract.** switching provider costs one
// line in main.go, and nothing here generates, stores or checks a code - that is auth.CodeManager.
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

// phone arrives canonical (998XXXXXXXXX, no plus) and each implementation respells it for its own
// api - exactly the kind of detail that should not leak past this boundary
type Sender interface {
	Send(ctx context.Context, phone, code string) error
}

// returned alongside the sender, so the startup log can say which one is live - the single most
// useful line when codes are not arriving
const (
	KindConsole  = "console"
	KindTelegram = "telegram"
)

const (
	// optional override. without it the choice follows whether the token is present, which is what
	// makes a laptop with an empty .env work out of the box.
	EnvSender = "VERIFY_SENDER"

	// Telegram Gateway (core.telegram.org/gateway/api) - one bearer token from gateway.telegram.org
	EnvTelegramToken = "TELEGRAM_GATEWAY_TOKEN"
)

// above any working link to Telegram, below the patience of somebody staring at a spinner
const sendTimeout = 10 * time.Second

// a struct rather than os.Getenv calls inside New, so the selection - the part that decides whether
// real money gets spent - can be tested as a table without a .env
type Settings struct {
	Sender        string // EnvSender, empty means "decide from the token below"
	TelegramToken string
}

func SettingsFromEnv() Settings {
	return Settings{
		Sender:        env(EnvSender),
		TelegramToken: env(EnvTelegramToken),
	}
}

func env(key string) string { return strings.TrimSpace(os.Getenv(key)) }

// New picks an implementation and reports which one by name. **naming a provider without its
// credentials is an error, never a quiet fall back to the console**: an api that boots green,
// answers 200 to every login and delivers nothing is discovered by the first real user.
func New(s Settings) (Sender, string, error) {
	kind := strings.ToLower(strings.TrimSpace(s.Sender))
	if kind == "" {
		if s.TelegramToken != "" {
			kind = KindTelegram
		} else {
			kind = KindConsole
		}
	}

	switch kind {
	case KindConsole:
		return &consoleSender{}, KindConsole, nil

	case KindTelegram:
		if s.TelegramToken == "" {
			return nil, "", fmt.Errorf("verify: %s=telegram but %s is empty", EnvSender, EnvTelegramToken)
		}
		// one client, so every send reuses a warm tls connection instead of paying a handshake
		client := &http.Client{Timeout: sendTimeout}
		return &telegramGateway{token: s.TelegramToken, client: client}, KindTelegram, nil

	default:
		return nil, "", fmt.Errorf("verify: %s=%q is not one of %q, %q", EnvSender, s.Sender, KindConsole, KindTelegram)
	}
}

// the provider's "not accepted" collapses to this: the endpoint treats every refusal the same, so
// the distinction lives in the log line rather than in the type
var errRefused = errors.New("verify: the provider refused the message")

// consoleSender prints the code instead of delivering it. **not a stub, the development provider**: it
// shouts on every send, because a server printing everybody's login codes must be impossible to miss.
type consoleSender struct{}

func (c *consoleSender) Send(_ context.Context, phone, code string) error {
	log.Printf("VERIFY CODE (NOT DELIVERED - console sender) %s -> %s", auth.MaskPhone(phone), code)
	return nil
}

// package telegram speaks to @domix_manager_bot: the updates its webhook receives, the one message it
// sends, and the link that opens it. It knows nothing about sessions or accounts.
//
// No bot library: one method out and a few fields in are the whole surface, as with internal/verify.
package telegram

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

const (
	EnvBotToken      = "TELEGRAM_BOT_TOKEN"
	EnvWebhookSecret = "TELEGRAM_WEBHOOK_SECRET"

	// sent by telegram on every webhook call, holding the secret_token given to setWebhook
	SecretHeader = "X-Telegram-Bot-Api-Secret-Token"

	// a constant like supportEmail: the link in every build has to name the bot this token drives
	BotUsername = "domix_manager_bot"
)

const sendTimeout = 10 * time.Second

var (
	tokenShape = regexp.MustCompile(`^[0-9]+:[A-Za-z0-9_-]{30,}$`)
	// telegram's own rule for secret_token is 1-256 of these; 32 is ours, so it cannot be guessed
	secretShape = regexp.MustCompile(`^[A-Za-z0-9_-]{32,256}$`)
)

type Settings struct {
	Token  string
	Secret string
}

func SettingsFromEnv() Settings {
	return Settings{
		Token:  strings.TrimSpace(os.Getenv(EnvBotToken)),
		Secret: strings.TrimSpace(os.Getenv(EnvWebhookSecret)),
	}
}

// Validate refuses a settings pair the bot cannot work with. Neither value is ever put in the error.
func (s Settings) Validate() error {
	if !tokenShape.MatchString(s.Token) {
		return fmt.Errorf("%s is empty or not a bot token", EnvBotToken)
	}
	if !secretShape.MatchString(s.Secret) {
		return fmt.Errorf("%s must be 32-256 characters of A-Z a-z 0-9 _ - (openssl rand -hex 32)", EnvWebhookSecret)
	}
	return nil
}

// SecretMatches is the webhook's whole authentication: the url is public and anyone can POST to it.
func SecretMatches(r *http.Request, secret string) bool {
	got := r.Header.Get(SecretHeader)
	return secret != "" && subtle.ConstantTimeCompare([]byte(got), []byte(secret)) == 1
}

// DeepLink opens the bot and makes telegram send `/start <payload>` once the user presses Start.
func DeepLink(payload string) string {
	return "https://t.me/" + BotUsername + "?start=" + url.QueryEscape(payload)
}

// the slice of an Update this bot reads; everything else telegram sends is ignored by the decoder
type Update struct {
	UpdateID int64    `json:"update_id"`
	Message  *Message `json:"message"`
}

type Message struct {
	// **nil for channel posts and anonymous group admins**, so every reader checks it
	From    *User    `json:"from"`
	Chat    Chat     `json:"chat"`
	Text    string   `json:"text"`
	Contact *Contact `json:"contact"`
}

type User struct {
	ID           int64  `json:"id"`
	LanguageCode string `json:"language_code"`
}

type Chat struct {
	ID   int64  `json:"id"`
	Type string `json:"type"`
}

type Contact struct {
	PhoneNumber string `json:"phone_number"`
	// the telegram account the number belongs to: zero for an address-book entry that is not a user
	UserID int64 `json:"user_id"`
}

// Reply is one sendMessage. A non-empty ContactButton draws the one-time keyboard holding the
// request-contact button; an empty one takes any keyboard away.
type Reply struct {
	ChatID        int64
	Text          string
	ContactButton string
}

type Bot struct {
	token  string
	client *http.Client
	base   string
}

func NewBot(token string) *Bot {
	return &Bot{token: token, client: &http.Client{Timeout: sendTimeout}, base: "https://api.telegram.org"}
}

func (b *Bot) Send(ctx context.Context, reply Reply) error {
	body := map[string]any{"chat_id": reply.ChatID, "text": reply.Text}
	if reply.ContactButton != "" {
		body["reply_markup"] = map[string]any{
			"keyboard":          [][]map[string]any{{{"text": reply.ContactButton, "request_contact": true}}},
			"one_time_keyboard": true,
			"resize_keyboard":   true,
		}
	} else {
		body["reply_markup"] = map[string]any{"remove_keyboard": true}
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, b.base+"/bot"+b.token+"/sendMessage", bytes.NewReader(encoded))
	if err != nil {
		return errors.New("telegram: could not build the request")
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := b.client.Do(req)
	if err != nil {
		return fmt.Errorf("telegram: sendMessage: %w", withoutURL(err))
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var answer struct {
			Description string `json:"description"`
		}
		_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&answer)
		return fmt.Errorf("telegram: sendMessage answered %d: %s", resp.StatusCode, answer.Description)
	}
	return nil
}

// **a *url.Error prints the url, and the url carries the bot token**, so a timeout logged as it
// comes would write the token into the journal
func withoutURL(err error) error {
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return urlErr.Err
	}
	return err
}

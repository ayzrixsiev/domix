package verify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Telegram Gateway - core.telegram.org/gateway/api.
//
// **A different product from the bot that logs users in today.** The bot needed the user to open a
// chat, press /start and share a contact; the Gateway is a paid delivery api that puts a code into
// the user's Telegram (falling back to sms on Telegram's side for numbers it can reach that way),
// and the user never leaves the Domix app. It is the primary provider because it is materially
// cheaper per message than an uzbek sms aggregator.
//
// One call, sendVerificationMessage, carrying our own code rather than asking Telegram to invent
// one: Telegram can generate a code and check it for us (code_length + checkVerificationStatus),
// and that is deliberately not used. It would put the source of truth about who is logged in inside
// somebody else's service, and the second provider (Eskiz) cannot do it at all - so the two
// providers would stop being interchangeable and this file would stop being a seam.
const telegramGatewayURL = "https://gatewayapi.telegram.org/sendVerificationMessage"

type telegramGateway struct {
	token  string
	client *http.Client
}

// the request Telegram accepts. phone_number is E.164 *with* the plus, which is the one detail that
// differs from the canonical form used everywhere else in this codebase.
type gatewayRequest struct {
	PhoneNumber string `json:"phone_number"`
	Code        string `json:"code"`
}

// every Gateway answer is this envelope: ok, plus either a result or an error string.
type gatewayResponse struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

func (t *telegramGateway) Send(ctx context.Context, phone, code string) error {
	body, err := json.Marshal(gatewayRequest{PhoneNumber: "+" + phone, Code: code})
	if err != nil {
		return fmt.Errorf("verify: encoding the gateway request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, telegramGatewayURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("verify: building the gateway request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+t.token)

	resp, err := t.client.Do(req)
	if err != nil {
		return fmt.Errorf("verify: telegram gateway unreachable: %w", err)
	}
	defer resp.Body.Close()

	// LimitReader because this decodes a body from a server we do not run: without it, a wedged or
	// hostile endpoint streaming forever is an allocation loop inside an http handler.
	var answer gatewayResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&answer); err != nil {
		return fmt.Errorf("verify: telegram gateway answered http %d with something that is not json: %w", resp.StatusCode, err)
	}

	// `ok` is the field that matters, not the status code: the Gateway reports a refused delivery
	// (no balance, a number it cannot reach, a code that is the wrong shape) inside a 200.
	if !answer.OK {
		return fmt.Errorf("%w: telegram gateway said %q (http %d)", errRefused, answer.Error, resp.StatusCode)
	}

	return nil
}

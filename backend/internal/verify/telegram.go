package verify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Telegram Gateway - core.telegram.org/gateway/api. a paid delivery api that puts a code into the user's
// Telegram without them leaving the app, at a fraction of what an sms costs here.
//
// it carries **our own code** rather than letting Telegram generate and check one: that would put the
// source of truth about who is logged in inside somebody else's service.
const telegramGatewayURL = "https://gatewayapi.telegram.org/sendVerificationMessage"

type telegramGateway struct {
	token  string
	client *http.Client
}

// phone_number is E.164 *with* the plus - the one detail that differs from the canonical form
type gatewayRequest struct {
	PhoneNumber string `json:"phone_number"`
	Code        string `json:"code"`
}

// every Gateway answer is this envelope: ok, plus a result or an error string
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

	// LimitReader: this body comes from a server we do not run, and one streaming forever would be
	// an allocation loop inside an http handler
	var answer gatewayResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&answer); err != nil {
		return fmt.Errorf("verify: telegram gateway answered http %d with something that is not json: %w", resp.StatusCode, err)
	}

	// `ok` matters, not the status code: the Gateway reports a refused delivery inside a 200
	if !answer.OK {
		return fmt.Errorf("%w: telegram gateway said %q (http %d)", errRefused, answer.Error, resp.StatusCode)
	}

	return nil
}

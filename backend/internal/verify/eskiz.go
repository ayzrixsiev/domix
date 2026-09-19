package verify

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
)

// Eskiz - notify.eskiz.uz/api, the uzbek sms aggregator (CLAUDE.md §3).
//
// The fallback provider, and the only one that reaches a sim with no Telegram on it. Two calls:
// POST /auth/login exchanges the dashboard credentials for a token, POST /message/sms/send spends
// money.
//
// **The token is cached for the life of the process and renewed only on a 401.** Eskiz's token is
// long-lived; logging in per message would double the round trips on the one call whose latency a
// user is watching, and would hammer an endpoint that is rate limited on their side.
const (
	eskizBaseURL = "https://notify.eskiz.uz/api"

	// the short number every Eskiz account sends from unless it has bought its own
	eskizDefaultFrom = "4546"

	// what gets replaced by the digits inside ESKIZ_TEMPLATE
	eskizCodePlaceholder = "{code}"
)

type eskiz struct {
	email    string
	password string
	from     string
	template string

	client *http.Client

	mu    sync.Mutex
	token string
}

// newEskiz refuses to build a sender that would burn money on rejected messages.
//
// **The message text is a required setting with no default, and that is the most important line in
// this file.** Eskiz only delivers text that it has already moderated (POST /user/template);
// anything else is rejected, and while an account is still in test status only three fixed strings
// send at all. A default here would be a string that has never been through moderation, so every
// send would fail - or worse, would succeed on the founder's moderated account and fail on the day
// the text is edited by one character. ESKIZ_TEMPLATE must be a copy of the approved text, which is
// why the flow asks for it rather than inventing it.
func newEskiz(s Settings, client *http.Client) (Sender, error) {
	if s.EskizEmail == "" || s.EskizPassword == "" {
		return nil, fmt.Errorf("verify: eskiz needs both %s and %s", EnvEskizEmail, EnvEskizPassword)
	}
	if s.EskizTemplate == "" {
		return nil, fmt.Errorf("verify: %s must hold the exact text Eskiz has moderated, with %s where the digits go",
			EnvEskizTemplate, eskizCodePlaceholder)
	}
	if !strings.Contains(s.EskizTemplate, eskizCodePlaceholder) {
		return nil, fmt.Errorf("verify: %s does not contain %s, so the message would carry no code",
			EnvEskizTemplate, eskizCodePlaceholder)
	}

	from := s.EskizFrom
	if from == "" {
		from = eskizDefaultFrom
	}

	return &eskiz{
		email:    s.EskizEmail,
		password: s.EskizPassword,
		from:     from,
		template: s.EskizTemplate,
		client:   client,
	}, nil
}

func (e *eskiz) Send(ctx context.Context, phone, code string) error {
	message := strings.ReplaceAll(e.template, eskizCodePlaceholder, code)

	token, err := e.authToken(ctx, false)
	if err != nil {
		return err
	}

	status, body, err := e.postMessage(ctx, token, phone, message)
	if err != nil {
		return err
	}

	// the cached token expired, or was revoked in the dashboard. log in again and send once more -
	// once, not in a loop: a 401 on a freshly minted token means the credentials themselves are
	// wrong, and retrying that forever is how an api hangs instead of reporting a misconfiguration.
	if status == http.StatusUnauthorized {
		if token, err = e.authToken(ctx, true); err != nil {
			return err
		}
		if status, body, err = e.postMessage(ctx, token, phone, message); err != nil {
			return err
		}
	}

	if status < 200 || status > 299 {
		return fmt.Errorf("%w: eskiz answered http %d: %s", errRefused, status, body)
	}

	return nil
}

// authToken hands back the cached token, logging in when there is none or when renew says the one
// we have was just rejected.
//
// Two requests arriving together can both decide to log in, and that is left alone: Eskiz issues a
// token per call without invalidating the last, so the cost is one extra round trip in a race that
// happens at most once per process. Holding the mutex across the network call instead would block
// every other send behind it.
func (e *eskiz) authToken(ctx context.Context, renew bool) (string, error) {
	e.mu.Lock()
	cached := e.token
	e.mu.Unlock()

	if cached != "" && !renew {
		return cached, nil
	}

	form := url.Values{
		"email":    {e.email},
		"password": {e.password},
	}

	status, body, err := e.postForm(ctx, eskizBaseURL+"/auth/login", "", form)
	if err != nil {
		return "", err
	}
	if status < 200 || status > 299 {
		return "", fmt.Errorf("verify: eskiz refused the login (http %d): %s", status, body)
	}

	var answer struct {
		Data struct {
			Token string `json:"token"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(body), &answer); err != nil {
		return "", fmt.Errorf("verify: eskiz login answered something that is not json: %w", err)
	}
	if answer.Data.Token == "" {
		return "", fmt.Errorf("verify: eskiz login carried no token")
	}

	e.mu.Lock()
	e.token = answer.Data.Token
	e.mu.Unlock()

	return answer.Data.Token, nil
}

// postMessage is the call that costs money. mobile_phone is the canonical twelve digits with no
// plus, which is exactly the form Eskiz documents and the form auth.CanonicalPhone produces.
func (e *eskiz) postMessage(ctx context.Context, token, phone, message string) (int, string, error) {
	form := url.Values{
		"mobile_phone": {phone},
		"message":      {message},
		"from":         {e.from},
	}
	return e.postForm(ctx, eskizBaseURL+"/message/sms/send", token, form)
}

// postForm is the shared half of both calls: url-encoded form in, status and a bounded body out.
// The body is returned rather than decoded because the two callers want different things from it -
// a token, or a sentence for the log.
func (e *eskiz) postForm(ctx context.Context, endpoint, token string, form url.Values) (int, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return 0, "", fmt.Errorf("verify: building the eskiz request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := e.client.Do(req)
	if err != nil {
		return 0, "", fmt.Errorf("verify: eskiz unreachable: %w", err)
	}
	defer resp.Body.Close()

	// bounded, for the same reason the gateway's decode is: this body comes from a server we do not
	// run, and it ends up in a log line either way.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<10))
	if err != nil {
		return resp.StatusCode, "", fmt.Errorf("verify: reading the eskiz answer: %w", err)
	}

	return resp.StatusCode, strings.TrimSpace(string(body)), nil
}

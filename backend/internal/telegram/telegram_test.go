package telegram

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const testToken = "123456789:AAtesttokentesttokentesttokentest00"

// a failed send is logged as it comes, and the request url carries the token
func TestAFailedSendDoesNotPrintTheToken(t *testing.T) {
	bot := NewBot(testToken)
	bot.base = "http://127.0.0.1:1" // nothing listens there

	err := bot.Send(context.Background(), Reply{ChatID: 1, Text: "x"})
	if err == nil {
		t.Fatal("a send to nowhere succeeded")
	}
	if strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "AAtest") {
		t.Fatalf("the error carries the token: %v", err)
	}
}

func TestSecretMatches(t *testing.T) {
	secret := strings.Repeat("s", 40)
	for _, c := range []struct {
		header string
		want   bool
	}{
		{secret, true},
		{"", false},
		{secret + "x", false},
		{strings.Repeat("t", 40), false},
	} {
		req := httptest.NewRequest(http.MethodPost, "/", nil)
		if c.header != "" {
			req.Header.Set(SecretHeader, c.header)
		}
		if got := SecretMatches(req, secret); got != c.want {
			t.Fatalf("header %q: got %v", c.header, got)
		}
	}

	// an unset secret must never match an absent header
	if SecretMatches(httptest.NewRequest(http.MethodPost, "/", nil), "") {
		t.Fatal("an empty secret matched")
	}
}

func TestValidateRefusesAHalfFilledBot(t *testing.T) {
	good := Settings{Token: testToken, Secret: strings.Repeat("a", 64)}
	if err := good.Validate(); err != nil {
		t.Fatalf("a good pair refused: %v", err)
	}
	for _, s := range []Settings{
		{Token: "", Secret: good.Secret},
		{Token: testToken, Secret: ""},
		{Token: testToken, Secret: "short"},
		{Token: testToken, Secret: strings.Repeat("a", 40) + "!"},
	} {
		err := s.Validate()
		if err == nil {
			t.Fatalf("%+v passed", s)
		}
		if s.Secret != "" && strings.Contains(err.Error(), s.Secret) {
			t.Fatalf("the error prints the secret: %v", err)
		}
	}
}

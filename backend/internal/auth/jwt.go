package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// what jwt token will consists of
type TokenClaims struct {
	UserID int64  `json:"user_id"`
	Phone  string `json:"phone"`
	jwt.RegisteredClaims
}

// how long a login lasts. AddDate(years, months, days), so this is four calendar months - not
// 120 days: AddDate walks the calendar, so a token issued on 31 January expires on 31 May rather
// than drifting by the length of the months in between.
//
// it was a year, which is a long time to be unable to revoke anything. there is still no refresh
// token and no server-side revocation list, so the expiry *is* the only way a session ever ends -
// which is the whole argument for keeping it short. four months is the compromise: long enough that
// a customer who opens the app twice a year is not locked out, short enough that a leaked token is
// not a year-long problem. when refresh tokens exist this drops to hours and stops being a
// judgement call.
const tokenLifetimeMonths = 4

func GenerateJWT(userID int64, phone string, secretKey string) (string, error) {
	claims := TokenClaims{
		UserID: userID,
		Phone:  phone,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().AddDate(0, tokenLifetimeMonths, 0)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "domix_backend",
		},
	}

	// we use HMAC SHA-256 signing algorithm to generate jwt token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// server's secret key to mix it with existing jwt token
	signedToken, err := token.SignedString([]byte(secretKey))
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

// func is used to validate a user from incoming api requests
func ValidateJWT(tokenString string, secretKey string) (*TokenClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &TokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(secretKey), nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*TokenClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid or expired token")
	}

	return claims, nil
}

package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// **no role claim, deliberately**: a token lives four months and a role can change inside that, so
// every check reads the role from the database instead
type TokenClaims struct {
	UserID int64  `json:"user_id"`
	Phone  string `json:"phone"`
	jwt.RegisteredClaims
}

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

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	signedToken, err := token.SignedString([]byte(secretKey))
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

// the signing method is checked, not just the signature: without it a token could name "none"
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

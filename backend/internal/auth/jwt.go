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
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// func to generate jwt that lives 1 year
func GenerateJWT(userID int64, phone string, role string, secretKey string) (string, error) {
	claims := TokenClaims{
		UserID: userID,
		Phone:  phone,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(time.Now().AddDate(1, 0, 0)),
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
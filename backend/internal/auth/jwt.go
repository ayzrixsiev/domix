package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TokenClaims defines the payload embedded inside the encrypted JWT token.
// any API endpoint can read this later without hitting the database
type TokenClaims struct {
	UserID int64  `json:"user_id"`
	Phone  string `json:"phone"`
	Role   string `json:"role"` // e.g., "shop_owner" or "customer"
	jwt.RegisteredClaims
}

// GenerateJWT creates a cryptographically signed token for a verified user
func GenerateJWT(userID int64, phone string, role string, secretKey string) (string, error) {
	// 1. define the claims and expiration time (e.g., 30 days for mobile login convenience)
	claims := TokenClaims{
		UserID: userID,
		Phone:  phone,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "domix_backend",
		},
	}

	// 2. create the token using the HMAC SHA-256 signing algorithm
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// 3. sign the token with your server's secret key from your .env file
	signedToken, err := token.SignedString([]byte(secretKey))
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

// ValidateJWT is used by our protected API routes to verify incoming Flutter requests
func ValidateJWT(tokenString string, secretKey string) (*TokenClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &TokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Ensure the signing method hasn't been tampered with
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
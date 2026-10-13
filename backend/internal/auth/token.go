// Package auth implements password hashing, JWT access tokens and opaque refresh tokens.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims are the JWT claims carried by an access token.
type Claims struct {
	DeviceID string `json:"did,omitempty"`
	jwt.RegisteredClaims
}

// TokenIssuer signs and verifies access tokens.
type TokenIssuer struct {
	secret []byte
	ttl    time.Duration
}

// NewTokenIssuer builds an HS256 issuer.
func NewTokenIssuer(secret string, ttl time.Duration) *TokenIssuer {
	return &TokenIssuer{secret: []byte(secret), ttl: ttl}
}

// IssueAccess returns a signed access token for the user/device pair.
func (t *TokenIssuer) IssueAccess(userID, deviceID string, now time.Time) (string, time.Time, error) {
	exp := now.Add(t.ttl)
	claims := Claims{
		DeviceID: deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
			Issuer:    "personal-calendar",
		},
	}
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
	return s, exp, err
}

// ParseAccess validates the token and returns its claims.
func (t *TokenIssuer) ParseAccess(token string) (*Claims, error) {
	claims := &Claims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(tk *jwt.Token) (any, error) {
		if _, ok := tk.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return t.secret, nil
	}, jwt.WithIssuer("personal-calendar"), jwt.WithLeeway(30*time.Second))
	if err != nil || !parsed.Valid || claims.Subject == "" {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

// NewRefreshToken returns a random opaque token and its sha256 hex hash for storage.
func NewRefreshToken() (token, hash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	token = base64.RawURLEncoding.EncodeToString(b)
	return token, HashRefreshToken(token), nil
}

// HashRefreshToken hashes an opaque refresh token for lookup.
func HashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

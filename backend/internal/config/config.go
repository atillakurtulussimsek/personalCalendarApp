// Package config loads runtime configuration from environment variables.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds every runtime setting of the API server.
type Config struct {
	Addr              string
	DatabaseURL       string
	JWTSecret         string
	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	AllowRegistration bool
	CORSOrigins       []string
	RateLimitPerMin   int
	// TrustedProxies is the number of reverse proxies in front of the API
	// (0 = none, client IP from the TCP connection; N = Nth-from-right X-Forwarded-For entry).
	TrustedProxies int
	LogLevel       string
	// FCMServiceAccountJSON holds Firebase service-account credentials (raw JSON).
	// Empty disables push; FCM_SERVICE_ACCOUNT_FILE may point to the file instead.
	FCMServiceAccountJSON string
}

// Load reads configuration from the environment. Required values produce an error.
func Load() (Config, error) {
	cfg := Config{
		Addr:                  getenv("ADDR", ":8080"),
		DatabaseURL:           os.Getenv("DATABASE_URL"),
		JWTSecret:             os.Getenv("JWT_SECRET"),
		AccessTokenTTL:        getDuration("ACCESS_TOKEN_TTL", 15*time.Minute),
		RefreshTokenTTL:       getDuration("REFRESH_TOKEN_TTL", 30*24*time.Hour),
		AllowRegistration:     getBool("ALLOW_REGISTRATION", true),
		CORSOrigins:           splitList(getenv("CORS_ORIGINS", "*")),
		RateLimitPerMin:       getInt("RATE_LIMIT_PER_MIN", 300),
		TrustedProxies:        getInt("TRUSTED_PROXIES", 0),
		FCMServiceAccountJSON: os.Getenv("FCM_SERVICE_ACCOUNT_JSON"),
		LogLevel:              getenv("LOG_LEVEL", "info"),
	}
	if cfg.FCMServiceAccountJSON == "" {
		if path := os.Getenv("FCM_SERVICE_ACCOUNT_FILE"); path != "" {
			b, err := os.ReadFile(path)
			if err != nil {
				return cfg, fmt.Errorf("FCM_SERVICE_ACCOUNT_FILE: %w", err)
			}
			cfg.FCMServiceAccountJSON = string(b)
		}
	}
	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf("DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return cfg, fmt.Errorf("JWT_SECRET must be at least 32 characters")
	}
	return cfg, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return b
}

func getInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func getDuration(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return def
	}
	return d
}

func splitList(s string) []string {
	parts := strings.Split(s, ",")
	out := parts[:0]
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

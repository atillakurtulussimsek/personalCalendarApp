package auth

import (
	"testing"
	"time"
)

func TestPasswordRoundTrip(t *testing.T) {
	h, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	ok, err := VerifyPassword("correct horse battery staple", h)
	if err != nil || !ok {
		t.Fatalf("expected match, ok=%v err=%v", ok, err)
	}
	ok, _ = VerifyPassword("wrong", h)
	if ok {
		t.Fatal("expected mismatch")
	}
	if _, err := VerifyPassword("x", "garbage"); err == nil {
		t.Fatal("expected format error")
	}
}

func TestAccessToken(t *testing.T) {
	iss := NewTokenIssuer("0123456789abcdef0123456789abcdef", time.Minute)
	now := time.Now()
	tok, _, err := iss.IssueAccess("user-1", "dev-1", now)
	if err != nil {
		t.Fatal(err)
	}
	c, err := iss.ParseAccess(tok)
	if err != nil {
		t.Fatal(err)
	}
	if c.Subject != "user-1" || c.DeviceID != "dev-1" {
		t.Fatalf("unexpected claims %+v", c)
	}
	other := NewTokenIssuer("ffffffffffffffffffffffffffffffff", time.Minute)
	if _, err := other.ParseAccess(tok); err == nil {
		t.Fatal("token verified with wrong secret")
	}
	expired, _, _ := iss.IssueAccess("u", "d", now.Add(-2*time.Hour))
	if _, err := iss.ParseAccess(expired); err == nil {
		t.Fatal("expired token accepted")
	}
}

func TestRefreshToken(t *testing.T) {
	tok, hash, err := NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if HashRefreshToken(tok) != hash || len(hash) != 64 {
		t.Fatal("hash mismatch")
	}
}

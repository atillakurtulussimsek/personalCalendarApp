package server_test

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/config"
	"github.com/atillasimsek/personal-calendar/backend/internal/server"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

var (
	dbOnce sync.Once
	testDB *sql.DB
	dbErr  error
)

// testEnv spins up the full router against TEST_DATABASE_URL with a clean schema.
type testEnv struct {
	t     *testing.T
	srv   *httptest.Server
	store *store.Store
	token string
	// Clock lets tests move "now" forward.
	Clock *time.Time
}

func newEnv(t *testing.T) *testEnv {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping integration test")
	}
	dbOnce.Do(func() { testDB, dbErr = server.OpenDB(dsn) })
	if dbErr != nil {
		t.Fatalf("open db: %v", dbErr)
	}
	if err := server.Reset(testDB); err != nil {
		t.Fatalf("reset schema: %v", err)
	}
	now := time.Now().UTC().Truncate(time.Microsecond)
	st := store.New(testDB)
	st.Now = func() time.Time { return now }
	cfg := config.Config{
		JWTSecret: "test-secret-test-secret-test-secret-1234", AccessTokenTTL: time.Hour, RefreshTokenTTL: 24 * time.Hour,
		AllowRegistration: true, CORSOrigins: []string{"*"}, RateLimitPerMin: 100000,
	}
	h := server.NewRouter(cfg, st)
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &testEnv{t: t, srv: srv, store: st, Clock: &now}
}

type resp struct {
	Status int
	Body   map[string]any
	Raw    []byte
}

func (e *testEnv) do(method, path string, body any) resp {
	e.t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rdr)
	req.Header.Set("Content-Type", "application/json")
	if e.token != "" {
		req.Header.Set("Authorization", "Bearer "+e.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(res.Body)
	out := resp{Status: res.StatusCode, Raw: raw}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &out.Body)
	}
	return out
}

func (e *testEnv) must(method, path string, body any, want int) resp {
	e.t.Helper()
	r := e.do(method, path, body)
	if r.Status != want {
		e.t.Fatalf("%s %s: status %d want %d: %s", method, path, r.Status, want, r.Raw)
	}
	return r
}

// register creates a user and sets the bearer token; returns the default calendar id.
func (e *testEnv) register(email string) (refresh, defaultCal string) {
	e.t.Helper()
	r := e.must("POST", "/auth/register", map[string]any{
		"email": email, "password": "password123", "device_id": uuid.NewString(), "device_platform": "macos", "device_name": "test",
	}, 200)
	e.token = r.Body["access_token"].(string)
	cals := e.must("GET", "/calendars", nil, 200).Body["calendars"].([]any)
	return r.Body["refresh_token"].(string), cals[0].(map[string]any)["id"].(string)
}

func decode[T any](t *testing.T, raw []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("decode: %v: %s", err, raw)
	}
	return v
}

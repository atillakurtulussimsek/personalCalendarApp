// Package server builds the chi router with middleware and opens the database.
package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"
	"github.com/go-sql-driver/mysql"
	"github.com/golang-migrate/migrate/v4"
	mysqlmigrate "github.com/golang-migrate/migrate/v4/database/mysql"
	"github.com/golang-migrate/migrate/v4/source/iofs"

	"github.com/atillasimsek/personal-calendar/backend/internal/config"
	"github.com/atillasimsek/personal-calendar/backend/internal/handlers"
	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/migrations"
	"github.com/atillasimsek/personal-calendar/backend/internal/notify"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

// OpenDB opens a MySQL pool from a DSN (user:pass@tcp(host:3306)/db) and
// forces the settings the app relies on (UTC, parseTime, utf8mb4).
func OpenDB(dsn string) (*sql.DB, error) {
	cfg, err := mysql.ParseDSN(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	cfg.ParseTime = true
	cfg.Loc = time.UTC
	cfg.MultiStatements = true
	if cfg.Params == nil {
		cfg.Params = map[string]string{}
	}
	cfg.Params["charset"] = "utf8mb4"
	cfg.Params["time_zone"] = "'+00:00'"
	db, err := sql.Open("mysql", cfg.FormatDSN())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return db, nil
}

func newMigrator(db *sql.DB) (*migrate.Migrate, error) {
	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return nil, err
	}
	// Use a single pooled connection (not the whole pool) so Close() only returns
	// that connection instead of closing the application's *sql.DB.
	conn, err := db.Conn(context.Background())
	if err != nil {
		return nil, err
	}
	drv, err := mysqlmigrate.WithConnection(context.Background(), conn, &mysqlmigrate.Config{})
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return migrate.NewWithInstance("iofs", src, "mysql", drv)
}

// Migrate applies all pending embedded migrations.
func Migrate(db *sql.DB) error {
	m, err := newMigrator(db)
	if err != nil {
		return err
	}
	defer func() { _, _ = m.Close() }() // releases the pooled connection held by the driver
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return err
	}
	return nil
}

// Reset drops everything and re-applies migrations (used by tests).
func Reset(db *sql.DB) error {
	m, err := newMigrator(db)
	if err != nil {
		return err
	}
	if err := m.Drop(); err != nil {
		_, _ = m.Close()
		return err
	}
	_, _ = m.Close()
	return Migrate(db)
}

// NewRouter builds the HTTP handler. hub may be nil (no live sync).
func NewRouter(cfg config.Config, st *store.Store, hub *notify.Hub) http.Handler {
	r := chi.NewRouter()
	if cfg.TrustedProxies > 0 {
		r.Use(middleware.ClientIPFromXFFTrustedProxies(cfg.TrustedProxies))
	} else {
		r.Use(middleware.ClientIPFromRemoteAddr)
	}
	r.Use(requestLogger)
	r.Use(middleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler {
		timeout := middleware.Timeout(60 * time.Second)(next)
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/ws" {
				next.ServeHTTP(w, r) // long-lived connection
				return
			}
			timeout.ServeHTTP(w, r)
		})
	})
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   cfg.CORSOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300,
	}))
	r.Use(httprate.LimitBy(cfg.RateLimitPerMin, time.Minute, keyByClientIP))
	r.NotFound(func(w http.ResponseWriter, _ *http.Request) { httpx.WriteError(w, httpx.NotFound("route not found")) })
	r.MethodNotAllowed(func(w http.ResponseWriter, _ *http.Request) {
		httpx.WriteError(w, &httpx.APIError{Status: http.StatusMethodNotAllowed, Code: "method_not_allowed", Message: "method not allowed"})
	})
	h := handlers.New(cfg, st)
	h.Hub = hub
	h.AuthLimiter = httprate.LimitBy(20, time.Minute, keyByClientIP) // stricter limit on credential endpoints
	h.Mount(r)
	return r
}

// keyByClientIP buckets rate limits by the IP resolved by the ClientIPFrom* middleware.
func keyByClientIP(r *http.Request) (string, error) {
	return httprate.CanonicalizeIP(middleware.GetClientIP(r.Context())), nil
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		slog.Info("http", "method", r.Method, "path", r.URL.Path, "status", ww.Status(), "bytes", ww.BytesWritten(), "dur", time.Since(start).String(), "ip", middleware.GetClientIP(r.Context()))
	})
}

// Command api runs the Personal Calendar HTTP API.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/joho/godotenv"

	"github.com/atillasimsek/personal-calendar/backend/internal/config"
	"github.com/atillasimsek/personal-calendar/backend/internal/notify"
	"github.com/atillasimsek/personal-calendar/backend/internal/server"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run() error {
	_ = godotenv.Load() // .env is optional; real deployments use environment variables
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	setupLogger(cfg.LogLevel)

	db, err := server.OpenDB(cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer func() { _ = db.Close() }()
	if err := server.Migrate(db); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	slog.Info("migrations applied")

	var pusher notify.Pusher
	if fcm, err := notify.NewFCM(context.Background(), []byte(cfg.FCMServiceAccountJSON), db); err != nil {
		return err
	} else if fcm != nil {
		pusher = fcm
		slog.Info("fcm push enabled")
	}
	hub := notify.NewHub(pusher, 2*time.Second)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           server.NewRouter(cfg, store.New(db), hub),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	go func() {
		slog.Info("listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("listen", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	slog.Info("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return srv.Shutdown(ctx)
}

func setupLogger(level string) {
	var lvl slog.Level
	if err := lvl.UnmarshalText([]byte(level)); err != nil {
		lvl = slog.LevelInfo
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})))
}

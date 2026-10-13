// Package handlers wires HTTP routes to the store and auth packages.
package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/auth"
	"github.com/atillasimsek/personal-calendar/backend/internal/config"
	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/notify"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

// Handlers holds shared dependencies.
type Handlers struct {
	Cfg    config.Config
	Store  *store.Store
	Tokens *auth.TokenIssuer
	Now    func() time.Time
	// AuthLimiter, when set, wraps the credential endpoints (login/register).
	AuthLimiter func(http.Handler) http.Handler
	// Hub fans out change signals to other devices (may be nil).
	Hub *notify.Hub
}

// changed tells the hub that the user's data changed (no-op without a hub).
func (h *Handlers) changed(r *http.Request, seq int64) {
	if h.Hub == nil {
		return
	}
	if seq == 0 {
		s, err := h.Store.LastSeq(r.Context())
		if err != nil {
			return
		}
		seq = s
	}
	h.Hub.Changed(httpx.UserID(r.Context()), httpx.DeviceID(r.Context()), seq)
}

// New builds the handler set.
func New(cfg config.Config, st *store.Store) *Handlers {
	return &Handlers{
		Cfg: cfg, Store: st,
		Tokens: auth.NewTokenIssuer(cfg.JWTSecret, cfg.AccessTokenTTL),
		Now:    func() time.Time { return time.Now().UTC() },
	}
}

// Mount registers all routes on r.
func (h *Handlers) Mount(r chi.Router) {
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	r.Route("/auth", func(r chi.Router) {
		lim := func(next http.Handler) http.Handler { return next }
		if h.AuthLimiter != nil {
			lim = h.AuthLimiter
		}
		r.With(lim).Post("/register", h.register)
		r.With(lim).Post("/login", h.login)
		r.Post("/refresh", h.refresh)
		r.With(h.RequireAuth).Post("/logout", h.logout)
		r.With(h.RequireAuth).Get("/me", h.me)
	})
	r.Group(func(r chi.Router) {
		r.Use(h.RequireAuth)
		r.Route("/calendars", func(r chi.Router) {
			r.Get("/", h.listCalendars)
			r.Post("/", h.createCalendar)
			r.Get("/{id}", h.getCalendar)
			r.Put("/{id}", h.updateCalendar)
			r.Delete("/{id}", h.deleteCalendar)
		})
		r.Route("/events", func(r chi.Router) {
			r.Get("/", h.listEvents)
			r.Post("/", h.createEvent)
			r.Get("/{id}", h.getEvent)
			r.Put("/{id}", h.updateEvent)
			r.Delete("/{id}", h.deleteEvent)
		})
		r.Route("/notes", func(r chi.Router) {
			r.Get("/", h.listNotes)
			r.Post("/", h.createNote)
			r.Get("/{id}", h.getNote)
			r.Put("/{id}", h.updateNote)
			r.Delete("/{id}", h.deleteNote)
		})
		r.Route("/sync", func(r chi.Router) {
			r.Get("/", h.pull)
			r.Post("/", h.push)
		})
		r.Get("/ws", h.websocket)
		r.Route("/devices", func(r chi.Router) {
			r.Get("/", h.listDevices)
			r.Post("/", h.registerDevice)
			r.Put("/{id}", h.updateDevice)
			r.Delete("/{id}", h.deleteDevice)
		})
	})
}

// RequireAuth validates the bearer access token.
func (h *Handlers) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hdr := r.Header.Get("Authorization")
		token := strings.TrimPrefix(hdr, "Bearer ")
		if !strings.HasPrefix(hdr, "Bearer ") {
			token = r.URL.Query().Get("token") // WebSocket clients cannot always set headers
		}
		if token == "" {
			httpx.WriteError(w, httpx.Unauthorized("missing bearer token"))
			return
		}
		claims, err := h.Tokens.ParseAccess(token)
		if err != nil {
			httpx.WriteError(w, httpx.Unauthorized("invalid or expired token"))
			return
		}
		next.ServeHTTP(w, r.WithContext(httpx.WithUser(r.Context(), claims.Subject, claims.DeviceID)))
	})
}

// mapErr converts store errors to API errors.
func mapErr(err error) error {
	var ve *store.ErrValidation
	var ce *store.ErrConflict
	switch {
	case errors.Is(err, store.ErrNotFound):
		return httpx.NotFound("record not found")
	case errors.As(err, &ve):
		return httpx.Validation(ve.Msg)
	case errors.As(err, &ce):
		return &httpx.APIError{Status: http.StatusConflict, Code: "version_conflict", Message: "record was modified; reload and retry"}
	}
	return err
}

// idParam validates the {id} path parameter as a UUID.
func idParam(r *http.Request) (string, error) {
	id := chi.URLParam(r, "id")
	if _, err := uuid.Parse(id); err != nil {
		return "", httpx.BadRequest("invalid id")
	}
	return strings.ToLower(id), nil
}

// ensureID validates a client-supplied id or generates one.
func ensureID(id string) (string, error) {
	if id == "" {
		return uuid.NewString(), nil
	}
	if _, err := uuid.Parse(id); err != nil {
		return "", httpx.Validation("id must be a UUID")
	}
	return strings.ToLower(id), nil
}

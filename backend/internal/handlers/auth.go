package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/auth"
	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	// Device is optional; when given a device row is created/updated and the session is bound to it.
	DeviceID       string `json:"device_id,omitempty"`
	DevicePlatform string `json:"device_platform,omitempty"`
	DeviceName     string `json:"device_name,omitempty"`
}

type tokenResponse struct {
	AccessToken  string     `json:"access_token"`
	ExpiresAt    time.Time  `json:"expires_at"`
	RefreshToken string     `json:"refresh_token"`
	User         model.User `json:"user"`
	DeviceID     string     `json:"device_id,omitempty"`
}

func normalizeEmail(e string) (string, error) {
	e = strings.ToLower(strings.TrimSpace(e))
	if a, err := mail.ParseAddress(e); err != nil || a.Address != e {
		return "", httpx.Validation("invalid email address")
	}
	return e, nil
}

func (h *Handlers) register(w http.ResponseWriter, r *http.Request) {
	if !h.Cfg.AllowRegistration {
		httpx.WriteError(w, httpx.Forbidden("registration is closed"))
		return
	}
	var in credentials
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	email, err := normalizeEmail(in.Email)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if len(in.Password) < 8 || len(in.Password) > 256 {
		httpx.WriteError(w, httpx.Validation("password must be 8-256 characters"))
		return
	}
	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	q := h.Store.Queries()
	ctx := r.Context()
	if _, err := q.GetUserByEmail(ctx, email); err == nil {
		httpx.WriteError(w, httpx.Conflict("email already registered"))
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		httpx.WriteError(w, err)
		return
	}
	now := h.Now()
	userID := uuid.NewString()
	if err := q.CreateUser(ctx, db.CreateUserParams{ID: userID, Email: email, PasswordHash: hash, CreatedAt: now, UpdatedAt: now}); err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := h.Store.EnsureDefaultCalendar(ctx, userID, uuid.NewString()); err != nil {
		httpx.WriteError(w, err)
		return
	}
	user, err := q.GetUserByID(ctx, userID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	h.issueSession(w, r, user, in)
}

func (h *Handlers) login(w http.ResponseWriter, r *http.Request) {
	var in credentials
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	email, err := normalizeEmail(in.Email)
	if err != nil {
		httpx.WriteError(w, httpx.Unauthorized("invalid credentials"))
		return
	}
	user, err := h.Store.Queries().GetUserByEmail(r.Context(), email)
	if errors.Is(err, sql.ErrNoRows) {
		// burn time so missing users are not distinguishable from wrong passwords
		_, _ = auth.VerifyPassword(in.Password, "$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
		httpx.WriteError(w, httpx.Unauthorized("invalid credentials"))
		return
	} else if err != nil {
		httpx.WriteError(w, err)
		return
	}
	ok, err := auth.VerifyPassword(in.Password, user.PasswordHash)
	if err != nil || !ok {
		httpx.WriteError(w, httpx.Unauthorized("invalid credentials"))
		return
	}
	h.issueSession(w, r, user, in)
}

// issueSession upserts the optional device, stores a refresh session and returns tokens.
func (h *Handlers) issueSession(w http.ResponseWriter, r *http.Request, user db.User, in credentials) {
	ctx := r.Context()
	q := h.Store.Queries()
	now := h.Now()
	deviceID := ""
	if in.DeviceID != "" {
		id, err := ensureID(in.DeviceID)
		if err != nil {
			httpx.WriteError(w, err)
			return
		}
		platform := strings.ToLower(in.DevicePlatform)
		if platform != "android" && platform != "macos" {
			platform = "other"
		}
		err = q.UpsertDevice(ctx, db.UpsertDeviceParams{
			ID: id, UserID: user.ID, Platform: platform, Name: in.DeviceName, PushToken: sql.NullString{}, CreatedAt: now, UpdatedAt: now,
		})
		if err != nil {
			httpx.WriteError(w, err)
			return
		}
		// one live session per device
		_ = q.RevokeSessionsByDevice(ctx, db.RevokeSessionsByDeviceParams{RevokedAt: sql.NullTime{Time: now, Valid: true}, UserID: user.ID, DeviceID: sql.NullString{String: id, Valid: true}})
		deviceID = id
	}
	resp, err := h.newTokens(r, user, deviceID, now)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}

func (h *Handlers) newTokens(r *http.Request, user db.User, deviceID string, now time.Time) (tokenResponse, error) {
	access, exp, err := h.Tokens.IssueAccess(user.ID, deviceID, now)
	if err != nil {
		return tokenResponse{}, err
	}
	refresh, hash, err := auth.NewRefreshToken()
	if err != nil {
		return tokenResponse{}, err
	}
	err = h.Store.Queries().CreateSession(r.Context(), db.CreateSessionParams{
		ID: uuid.NewString(), UserID: user.ID, DeviceID: model.ToNullString(nilIfEmpty(deviceID)),
		RefreshTokenHash: hash, ExpiresAt: now.Add(h.Cfg.RefreshTokenTTL), CreatedAt: now,
	})
	if err != nil {
		return tokenResponse{}, err
	}
	return tokenResponse{AccessToken: access, ExpiresAt: exp, RefreshToken: refresh, User: model.UserFromRow(user), DeviceID: deviceID}, nil
}

func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// refresh rotates the refresh token: the old one is revoked, a new pair is issued.
func (h *Handlers) refresh(w http.ResponseWriter, r *http.Request) {
	var in refreshRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	ctx := r.Context()
	q := h.Store.Queries()
	now := h.Now()
	sess, err := q.GetSessionByTokenHash(ctx, auth.HashRefreshToken(in.RefreshToken))
	if errors.Is(err, sql.ErrNoRows) || (err == nil && (sess.RevokedAt.Valid || sess.ExpiresAt.Before(now))) {
		httpx.WriteError(w, httpx.Unauthorized("invalid refresh token"))
		return
	} else if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := q.RevokeSession(ctx, db.RevokeSessionParams{RevokedAt: sql.NullTime{Time: now, Valid: true}, ID: sess.ID}); err != nil {
		httpx.WriteError(w, err)
		return
	}
	user, err := q.GetUserByID(ctx, sess.UserID)
	if err != nil {
		httpx.WriteError(w, httpx.Unauthorized("invalid refresh token"))
		return
	}
	resp, err := h.newTokens(r, user, sess.DeviceID.String, now)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}

func (h *Handlers) logout(w http.ResponseWriter, r *http.Request) {
	var in refreshRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	q := h.Store.Queries()
	sess, err := q.GetSessionByTokenHash(r.Context(), auth.HashRefreshToken(in.RefreshToken))
	if err == nil && sess.UserID == httpx.UserID(r.Context()) {
		_ = q.RevokeSession(r.Context(), db.RevokeSessionParams{RevokedAt: sql.NullTime{Time: h.Now(), Valid: true}, ID: sess.ID})
	}
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

func (h *Handlers) me(w http.ResponseWriter, r *http.Request) {
	user, err := h.Store.Queries().GetUserByID(r.Context(), httpx.UserID(r.Context()))
	if err != nil {
		httpx.WriteError(w, httpx.Unauthorized("user not found"))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, model.UserFromRow(user))
}

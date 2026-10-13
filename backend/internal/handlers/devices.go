package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

type deviceInput struct {
	ID        string  `json:"id"`
	Platform  string  `json:"platform"`
	Name      string  `json:"name"`
	PushToken *string `json:"push_token"`
}

func (h *Handlers) listDevices(w http.ResponseWriter, r *http.Request) {
	rows, err := h.Store.Queries().ListDevices(r.Context(), httpx.UserID(r.Context()))
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	out := make([]model.Device, 0, len(rows))
	for _, d := range rows {
		out = append(out, model.DeviceFromRow(d))
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"devices": out})
}

func (h *Handlers) registerDevice(w http.ResponseWriter, r *http.Request) {
	var in deviceInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	id, err := ensureID(in.ID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	platform := strings.ToLower(in.Platform)
	if platform != "android" && platform != "macos" {
		platform = "other"
	}
	now := h.Now()
	userID := httpx.UserID(r.Context())
	q := h.Store.Queries()
	err = q.UpsertDevice(r.Context(), db.UpsertDeviceParams{
		ID: id, UserID: userID, Platform: platform, Name: in.Name, PushToken: model.ToNullString(in.PushToken), CreatedAt: now, UpdatedAt: now,
	})
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	row, err := q.GetDevice(r.Context(), db.GetDeviceParams{ID: id, UserID: userID})
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, model.DeviceFromRow(row))
}

func (h *Handlers) updateDevice(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var in deviceInput
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	userID := httpx.UserID(r.Context())
	q := h.Store.Queries()
	if _, err := q.GetDevice(r.Context(), db.GetDeviceParams{ID: id, UserID: userID}); errors.Is(err, sql.ErrNoRows) {
		httpx.WriteError(w, httpx.NotFound("device not found"))
		return
	} else if err != nil {
		httpx.WriteError(w, err)
		return
	}
	err = q.UpdateDevicePushToken(r.Context(), db.UpdateDevicePushTokenParams{PushToken: model.ToNullString(in.PushToken), UpdatedAt: h.Now(), ID: id, UserID: userID})
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	row, _ := q.GetDevice(r.Context(), db.GetDeviceParams{ID: id, UserID: userID})
	httpx.WriteJSON(w, http.StatusOK, model.DeviceFromRow(row))
}

func (h *Handlers) deleteDevice(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	userID := httpx.UserID(r.Context())
	now := h.Now()
	q := h.Store.Queries()
	if err := q.SoftDeleteDevice(r.Context(), db.SoftDeleteDeviceParams{DeletedAt: sql.NullTime{Time: now, Valid: true}, UpdatedAt: now, ID: id, UserID: userID}); err != nil {
		httpx.WriteError(w, err)
		return
	}
	_ = q.RevokeSessionsByDevice(r.Context(), db.RevokeSessionsByDeviceParams{RevokedAt: sql.NullTime{Time: now, Valid: true}, UserID: userID, DeviceID: sql.NullString{String: id, Valid: true}})
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

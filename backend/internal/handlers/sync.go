package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

// pull handles GET /sync?since=<seq>&limit=<n>.
func (h *Handlers) pull(w http.ResponseWriter, r *http.Request) {
	since, err := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	if err != nil && r.URL.Query().Get("since") != "" {
		httpx.WriteError(w, httpx.BadRequest("since must be an integer"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	userID := httpx.UserID(r.Context())
	out, err := h.Store.Pull(r.Context(), userID, since, int32(limit))
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	h.touchDevice(r)
	httpx.WriteJSON(w, http.StatusOK, out)
}

type pushRequest struct {
	Items []store.PushItem `json:"items"`
}

// push handles POST /sync with the client's outbox.
func (h *Handlers) push(w http.ResponseWriter, r *http.Request) {
	var in pushRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	if len(in.Items) > 1000 {
		httpx.WriteError(w, httpx.Validation("at most 1000 items per push"))
		return
	}
	out, err := h.Store.Push(r.Context(), httpx.UserID(r.Context()), in.Items)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	h.touchDevice(r)
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) touchDevice(r *http.Request) {
	if did := httpx.DeviceID(r.Context()); did != "" {
		_ = h.Store.Queries().TouchDeviceSync(r.Context(), db.TouchDeviceSyncParams{
			LastSyncAt: sql.NullTime{Time: h.Now(), Valid: true}, ID: did, UserID: httpx.UserID(r.Context()),
		})
	}
}

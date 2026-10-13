package handlers

import (
	"net/http"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
	"github.com/atillasimsek/personal-calendar/backend/internal/rrule"
)

// listEvents handles GET /events?from=&to=&expand=true.
// Without expand the raw rows overlapping the range are returned (recurring
// masters included); with expand every occurrence in the range is returned.
func (h *Handlers) listEvents(w http.ResponseWriter, r *http.Request) {
	qs := r.URL.Query()
	from, err := parseTime(qs.Get("from"))
	if err != nil {
		httpx.WriteError(w, httpx.BadRequest("from must be RFC3339"))
		return
	}
	to, err := parseTime(qs.Get("to"))
	if err != nil {
		httpx.WriteError(w, httpx.BadRequest("to must be RFC3339"))
		return
	}
	if from.IsZero() {
		from = h.Now().AddDate(0, -1, 0)
	}
	if to.IsZero() {
		to = from.AddDate(0, 2, 0)
	}
	if !to.After(from) || to.Sub(from) > 366*24*time.Hour*2 {
		httpx.WriteError(w, httpx.BadRequest("range must be positive and at most two years"))
		return
	}
	userID := httpx.UserID(r.Context())
	events, err := h.Store.ListEvents(r.Context(), userID, from, to)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if qs.Get("expand") != "true" {
		httpx.WriteJSON(w, http.StatusOK, map[string]any{"events": events})
		return
	}
	var seriesIDs []string
	for _, e := range events {
		if e.Rrule != nil {
			seriesIDs = append(seriesIDs, e.ID)
		}
	}
	exceptions, err := h.Store.ListExceptions(r.Context(), userID, seriesIDs)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	occ, err := rrule.Expand(events, exceptions, from, to)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"occurrences": occ})
}

func parseTime(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	t, err := time.Parse(time.RFC3339, s)
	return t.UTC(), err
}

func (h *Handlers) createEvent(w http.ResponseWriter, r *http.Request) {
	var in model.Event
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	id, err := ensureID(in.ID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	in.ID = id
	out, err := h.Store.CreateEvent(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, out)
}

func (h *Handlers) getEvent(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	out, err := h.Store.GetEvent(r.Context(), httpx.UserID(r.Context()), id)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) updateEvent(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var in model.Event
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	in.ID = id
	out, err := h.Store.UpdateEvent(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) deleteEvent(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := h.Store.DeleteEvent(r.Context(), httpx.UserID(r.Context()), id); err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

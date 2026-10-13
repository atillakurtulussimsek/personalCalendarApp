package handlers

import (
	"net/http"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func (h *Handlers) listCalendars(w http.ResponseWriter, r *http.Request) {
	out, err := h.Store.ListCalendars(r.Context(), httpx.UserID(r.Context()))
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"calendars": out})
}

func (h *Handlers) createCalendar(w http.ResponseWriter, r *http.Request) {
	var in model.Calendar
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
	out, err := h.Store.CreateCalendar(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, out)
}

func (h *Handlers) getCalendar(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	out, err := h.Store.GetCalendar(r.Context(), httpx.UserID(r.Context()), id)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) updateCalendar(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var in model.Calendar
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	in.ID = id
	out, err := h.Store.UpdateCalendar(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) deleteCalendar(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := h.Store.DeleteCalendar(r.Context(), httpx.UserID(r.Context()), id); err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

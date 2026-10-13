package handlers

import (
	"net/http"
	"strconv"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

// listNotes handles GET /notes?q=&tag=&event_id=&limit=&offset=.
func (h *Handlers) listNotes(w http.ResponseWriter, r *http.Request) {
	qs := r.URL.Query()
	limit, _ := strconv.Atoi(qs.Get("limit"))
	offset, _ := strconv.Atoi(qs.Get("offset"))
	f := store.NoteFilter{Query: qs.Get("q"), Tag: qs.Get("tag"), EventID: qs.Get("event_id"), Limit: int32(limit), Offset: int32(max(offset, 0))}
	out, err := h.Store.ListNotes(r.Context(), httpx.UserID(r.Context()), f)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"notes": out})
}

func (h *Handlers) createNote(w http.ResponseWriter, r *http.Request) {
	var in model.Note
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
	out, err := h.Store.CreateNote(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, out)
}

func (h *Handlers) getNote(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	out, err := h.Store.GetNote(r.Context(), httpx.UserID(r.Context()), id)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) updateNote(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var in model.Note
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	in.ID = id
	out, err := h.Store.UpdateNote(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) deleteNote(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := h.Store.DeleteNote(r.Context(), httpx.UserID(r.Context()), id); err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

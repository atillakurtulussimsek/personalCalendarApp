package handlers

import (
	"net/http"
	"strconv"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func (h *Handlers) listTasks(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	out, err := h.Store.ListTasks(r.Context(), httpx.UserID(r.Context()), int32(limit), int32(max(offset, 0)))
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"tasks": out})
}

func (h *Handlers) createTask(w http.ResponseWriter, r *http.Request) {
	var in model.Task
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
	out, err := h.Store.CreateTask(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	h.changed(r, out.ServerSeq)
	httpx.WriteJSON(w, http.StatusCreated, out)
}

func (h *Handlers) getTask(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	out, err := h.Store.GetTask(r.Context(), httpx.UserID(r.Context()), id)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) updateTask(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	var in model.Task
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, err)
		return
	}
	in.ID = id
	out, err := h.Store.UpdateTask(r.Context(), httpx.UserID(r.Context()), in)
	if err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	h.changed(r, out.ServerSeq)
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handlers) deleteTask(w http.ResponseWriter, r *http.Request) {
	id, err := idParam(r)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if err := h.Store.DeleteTask(r.Context(), httpx.UserID(r.Context()), id); err != nil {
		httpx.WriteError(w, mapErr(err))
		return
	}
	h.changed(r, 0)
	httpx.WriteJSON(w, http.StatusNoContent, nil)
}

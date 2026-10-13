// Package httpx contains small HTTP helpers: JSON encoding, the uniform error
// envelope and request-scoped context values.
package httpx

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
)

// APIError is the uniform error payload: {"error": {"code", "message"}}.
type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

// Common error constructors.
func BadRequest(msg string) *APIError { return &APIError{http.StatusBadRequest, "bad_request", msg} }
func Validation(msg string) *APIError {
	return &APIError{http.StatusUnprocessableEntity, "validation_error", msg}
}
func Unauthorized(msg string) *APIError {
	return &APIError{http.StatusUnauthorized, "unauthorized", msg}
}
func Forbidden(msg string) *APIError { return &APIError{http.StatusForbidden, "forbidden", msg} }
func NotFound(msg string) *APIError  { return &APIError{http.StatusNotFound, "not_found", msg} }
func Conflict(msg string) *APIError  { return &APIError{http.StatusConflict, "conflict", msg} }
func Internal() *APIError {
	return &APIError{http.StatusInternalServerError, "internal_error", "internal server error"}
}

// WriteJSON encodes v as JSON with the given status.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("write json", "err", err)
	}
}

// WriteError writes err in the uniform envelope. Unknown errors become 500.
func WriteError(w http.ResponseWriter, err error) {
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		slog.Error("unhandled error", "err", err)
		apiErr = Internal()
	}
	WriteJSON(w, apiErr.Status, map[string]any{"error": apiErr})
}

// DecodeJSON strictly decodes a JSON body (max 2 MiB, unknown fields rejected).
func DecodeJSON(r *http.Request, v any) error {
	body := http.MaxBytesReader(nil, r.Body, 2<<20)
	dec := json.NewDecoder(body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		if errors.Is(err, io.EOF) {
			return BadRequest("empty request body")
		}
		return BadRequest("invalid JSON: " + err.Error())
	}
	if dec.More() {
		return BadRequest("unexpected trailing data")
	}
	return nil
}

type ctxKey int

const (
	ctxUserID ctxKey = iota
	ctxDeviceID
)

// WithUser stores the authenticated user and device id in ctx.
func WithUser(ctx context.Context, userID, deviceID string) context.Context {
	ctx = context.WithValue(ctx, ctxUserID, userID)
	return context.WithValue(ctx, ctxDeviceID, deviceID)
}

// UserID returns the authenticated user id or "".
func UserID(ctx context.Context) string {
	v, _ := ctx.Value(ctxUserID).(string)
	return v
}

// DeviceID returns the authenticated device id or "".
func DeviceID(ctx context.Context) string {
	v, _ := ctx.Value(ctxDeviceID).(string)
	return v
}

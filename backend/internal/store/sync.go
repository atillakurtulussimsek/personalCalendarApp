package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

// Entity names accepted by the sync protocol.
const (
	EntityCalendar = "calendar"
	EntityEvent    = "event"
	EntityNote     = "note"
)

// Operations accepted by the sync protocol.
const (
	OpUpsert = "upsert"
	OpDelete = "delete"
)

// Push item statuses.
const (
	StatusApplied  = "applied"  // written as sent
	StatusConflict = "conflict" // server version kept; `current` carries it
	StatusRejected = "rejected" // validation failed; `error` explains
	StatusIgnored  = "ignored"  // no-op (e.g. delete of unknown id)
)

// PushItem is one outbox entry sent by a client.
type PushItem struct {
	Entity      string          `json:"entity"`
	Op          string          `json:"op"`
	ID          string          `json:"id"`
	BaseVersion int64           `json:"base_version"`
	UpdatedAt   time.Time       `json:"updated_at"`
	Data        json.RawMessage `json:"data,omitempty"`
}

// PushResult is the outcome of one PushItem.
type PushResult struct {
	Entity         string `json:"entity"`
	ID             string `json:"id"`
	Status         string `json:"status"`
	Version        int64  `json:"version,omitempty"`
	ServerSeq      int64  `json:"server_seq,omitempty"`
	ConflictCopyID string `json:"conflict_copy_id,omitempty"`
	Current        any    `json:"current,omitempty"`
	Error          string `json:"error,omitempty"`
}

// PushResponse is returned by POST /sync.
type PushResponse struct {
	Results []PushResult `json:"results"`
	LastSeq int64        `json:"last_seq"`
}

// PullResponse is returned by GET /sync.
type PullResponse struct {
	Calendars []model.Calendar `json:"calendars"`
	Events    []model.Event    `json:"events"`
	Notes     []model.Note     `json:"notes"`
	LastSeq   int64            `json:"last_seq"`
	HasMore   bool             `json:"has_more"`
}

// Pull returns every record changed after `since`, including tombstones.
func (s *Store) Pull(ctx context.Context, userID string, since int64, limit int32) (PullResponse, error) {
	if limit <= 0 || limit > 1000 {
		limit = 500
	}
	resp := PullResponse{Calendars: []model.Calendar{}, Events: []model.Event{}, Notes: []model.Note{}}
	err := s.tx(ctx, func(q *db.Queries) error {
		cals, err := q.PullCalendars(ctx, db.PullCalendarsParams{UserID: userID, ServerSeq: since, Limit: limit})
		if err != nil {
			return err
		}
		evs, err := q.PullEvents(ctx, db.PullEventsParams{UserID: userID, ServerSeq: since, Limit: limit})
		if err != nil {
			return err
		}
		nts, err := q.PullNotes(ctx, db.PullNotesParams{UserID: userID, ServerSeq: since, Limit: limit})
		if err != nil {
			return err
		}
		global, err := q.CurrentServerSeq(ctx)
		if err != nil {
			return err
		}
		// If any entity hit the limit, cap the page at the smallest "full" seq so
		// the client never skips rows of another entity.
		cutoff := global
		full := false
		if int32(len(cals)) == limit {
			full = true
			cutoff = min(cutoff, cals[len(cals)-1].ServerSeq)
		}
		if int32(len(evs)) == limit {
			full = true
			cutoff = min(cutoff, evs[len(evs)-1].ServerSeq)
		}
		if int32(len(nts)) == limit {
			full = true
			cutoff = min(cutoff, nts[len(nts)-1].ServerSeq)
		}
		for _, r := range cals {
			if r.ServerSeq <= cutoff {
				resp.Calendars = append(resp.Calendars, model.CalendarFromRow(r))
			}
		}
		for _, r := range evs {
			if r.ServerSeq <= cutoff {
				resp.Events = append(resp.Events, model.EventFromRow(r))
			}
		}
		for _, r := range nts {
			if r.ServerSeq <= cutoff {
				resp.Notes = append(resp.Notes, model.NoteFromRow(r))
			}
		}
		resp.LastSeq = cutoff
		resp.HasMore = full
		return nil
	})
	return resp, err
}

// Push applies a batch of client changes. Each item is handled in its own
// transaction so one bad item does not roll back the rest.
func (s *Store) Push(ctx context.Context, userID string, items []PushItem) (PushResponse, error) {
	resp := PushResponse{Results: make([]PushResult, 0, len(items))}
	for _, it := range items {
		res := PushResult{Entity: it.Entity, ID: it.ID}
		err := s.tx(ctx, func(q *db.Queries) error {
			r, err := s.applyItem(ctx, q, userID, it)
			if err != nil {
				return err
			}
			res = r
			return nil
		})
		if err != nil {
			var ve *ErrValidation
			if errors.As(err, &ve) {
				res.Status = StatusRejected
				res.Error = ve.Msg
			} else {
				return resp, err
			}
		}
		resp.Results = append(resp.Results, res)
	}
	last, err := s.LastSeq(ctx)
	if err != nil {
		return resp, err
	}
	resp.LastSeq = last
	return resp, nil
}

func (s *Store) applyItem(ctx context.Context, q *db.Queries, userID string, it PushItem) (PushResult, error) {
	if it.ID == "" {
		return PushResult{}, invalid("id is required")
	}
	if it.Op != OpUpsert && it.Op != OpDelete {
		return PushResult{}, invalid("unknown op %q", it.Op)
	}
	if it.UpdatedAt.IsZero() {
		it.UpdatedAt = s.Now()
	}
	switch it.Entity {
	case EntityCalendar:
		return s.applyCalendar(ctx, q, userID, it)
	case EntityEvent:
		return s.applyEvent(ctx, q, userID, it)
	case EntityNote:
		return s.applyNote(ctx, q, userID, it)
	default:
		return PushResult{}, invalid("unknown entity %q", it.Entity)
	}
}

// decide resolves a push against the current server row.
//
//	exists=false           → insert (upsert) / ignore (delete)
//	base == cur.version    → fast path, client is up to date
//	base != cur.version    → last-writer-wins on updated_at
func decide(exists bool, curVersion int64, curUpdated time.Time, it PushItem) (apply bool, conflict bool) {
	if !exists {
		return it.Op == OpUpsert, false
	}
	if it.BaseVersion == curVersion {
		return true, false
	}
	if it.UpdatedAt.After(curUpdated) {
		return true, true
	}
	return false, true
}

func (s *Store) applyCalendar(ctx context.Context, q *db.Queries, userID string, it PushItem) (PushResult, error) {
	res := PushResult{Entity: it.Entity, ID: it.ID}
	cur, err := q.GetCalendarForUpdate(ctx, db.GetCalendarForUpdateParams{ID: it.ID, UserID: userID})
	exists := err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return res, err
	}
	apply, _ := decide(exists, cur.Version, cur.UpdatedAt, it)
	if !apply {
		if !exists {
			res.Status = StatusIgnored
			return res, nil
		}
		res.Status = StatusConflict
		res.Version, res.ServerSeq, res.Current = cur.Version, cur.ServerSeq, model.CalendarFromRow(cur)
		return res, nil
	}
	var out model.Calendar
	if it.Op == OpDelete {
		out, err = deleteCalendarTx(ctx, q, userID, cur, it.UpdatedAt)
	} else {
		var c model.Calendar
		if err := decodeData(it.Data, &c); err != nil {
			return res, err
		}
		c.ID, c.UpdatedAt = it.ID, it.UpdatedAt
		var existing *db.Calendar
		if exists {
			existing = &cur
		}
		out, err = upsertCalendarTx(ctx, q, userID, c, existing, s.Now())
	}
	if err != nil {
		return res, err
	}
	res.Status, res.Version, res.ServerSeq = StatusApplied, out.Version, out.ServerSeq
	return res, nil
}

func (s *Store) applyEvent(ctx context.Context, q *db.Queries, userID string, it PushItem) (PushResult, error) {
	res := PushResult{Entity: it.Entity, ID: it.ID}
	cur, err := q.GetEventForUpdate(ctx, db.GetEventForUpdateParams{ID: it.ID, UserID: userID})
	exists := err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return res, err
	}
	apply, _ := decide(exists, cur.Version, cur.UpdatedAt, it)
	if !apply {
		if !exists {
			res.Status = StatusIgnored
			return res, nil
		}
		res.Status = StatusConflict
		res.Version, res.ServerSeq, res.Current = cur.Version, cur.ServerSeq, model.EventFromRow(cur)
		return res, nil
	}
	var out model.Event
	if it.Op == OpDelete {
		out, err = deleteEventTx(ctx, q, userID, cur, it.UpdatedAt)
	} else {
		var e model.Event
		if err := decodeData(it.Data, &e); err != nil {
			return res, err
		}
		e.ID, e.UpdatedAt = it.ID, it.UpdatedAt
		var existing *db.Event
		if exists {
			existing = &cur
		}
		out, err = upsertEventTx(ctx, q, userID, e, existing, s.Now())
	}
	if err != nil {
		return res, err
	}
	res.Status, res.Version, res.ServerSeq = StatusApplied, out.Version, out.ServerSeq
	return res, nil
}

func (s *Store) applyNote(ctx context.Context, q *db.Queries, userID string, it PushItem) (PushResult, error) {
	res := PushResult{Entity: it.Entity, ID: it.ID}
	cur, err := q.GetNoteForUpdate(ctx, db.GetNoteForUpdateParams{ID: it.ID, UserID: userID})
	exists := err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return res, err
	}
	apply, conflict := decide(exists, cur.Version, cur.UpdatedAt, it)

	var incoming model.Note
	if it.Op == OpUpsert {
		if err := decodeData(it.Data, &incoming); err != nil {
			return res, err
		}
		incoming.ID, incoming.UpdatedAt = it.ID, it.UpdatedAt
	}

	// Never lose note text: when a real conflict changes the body, keep the
	// losing body as a separate "(çakışan kopya)" note.
	if conflict && exists && !cur.DeletedAt.Valid {
		switch {
		case !apply && it.Op == OpUpsert && incoming.Body != cur.Body:
			id, err := saveConflictCopyTx(ctx, q, userID, incoming, s.Now())
			if err != nil {
				return res, err
			}
			res.ConflictCopyID = id
		case apply && it.Op == OpUpsert && incoming.Body != cur.Body:
			id, err := saveConflictCopyTx(ctx, q, userID, model.NoteFromRow(cur), s.Now())
			if err != nil {
				return res, err
			}
			res.ConflictCopyID = id
		case apply && it.Op == OpDelete:
			// Client deleted a note the server changed meanwhile: keep the server text.
			id, err := saveConflictCopyTx(ctx, q, userID, model.NoteFromRow(cur), s.Now())
			if err != nil {
				return res, err
			}
			res.ConflictCopyID = id
		}
	}

	if !apply {
		if !exists {
			res.Status = StatusIgnored
			return res, nil
		}
		res.Status = StatusConflict
		res.Version, res.ServerSeq, res.Current = cur.Version, cur.ServerSeq, model.NoteFromRow(cur)
		return res, nil
	}
	var out model.Note
	if it.Op == OpDelete {
		out, err = deleteNoteTx(ctx, q, userID, cur, it.UpdatedAt)
	} else {
		var existing *db.Note
		if exists {
			existing = &cur
		}
		out, err = upsertNoteTx(ctx, q, userID, incoming, existing, s.Now())
	}
	if err != nil {
		return res, err
	}
	res.Status, res.Version, res.ServerSeq = StatusApplied, out.Version, out.ServerSeq
	return res, nil
}

func decodeData(raw json.RawMessage, v any) error {
	if len(raw) == 0 {
		return invalid("data is required for upsert")
	}
	if err := json.Unmarshal(raw, v); err != nil {
		return invalid("invalid data: %v", err)
	}
	return nil
}

var _ = fmt.Sprintf

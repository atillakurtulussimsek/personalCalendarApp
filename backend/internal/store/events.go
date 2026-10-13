package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/teambition/rrule-go"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func validateEvent(ctx context.Context, q *db.Queries, userID string, e *model.Event) error {
	e.Title = strings.TrimSpace(e.Title)
	if e.Title == "" {
		return invalid("event title is required")
	}
	if len(e.Title) > 512 {
		return invalid("event title too long")
	}
	if e.CalendarID == "" {
		return invalid("calendar_id is required")
	}
	cal, err := q.GetCalendar(ctx, db.GetCalendarParams{ID: e.CalendarID, UserID: userID})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && cal.DeletedAt.Valid) {
		return invalid("calendar %s not found", e.CalendarID)
	} else if err != nil {
		return err
	}
	if e.StartAt.IsZero() || e.EndAt.IsZero() {
		return invalid("start_at and end_at are required")
	}
	if e.EndAt.Before(e.StartAt) {
		return invalid("end_at must not be before start_at")
	}
	if e.Timezone == "" {
		e.Timezone = "UTC"
	}
	if _, err := time.LoadLocation(e.Timezone); err != nil {
		return invalid("unknown timezone %q", e.Timezone)
	}
	if e.Rrule != nil {
		r := strings.TrimSpace(strings.TrimPrefix(*e.Rrule, "RRULE:"))
		if r == "" {
			e.Rrule = nil
		} else {
			if _, err := rrule.StrToRRule(r); err != nil {
				return invalid("invalid rrule: %v", err)
			}
			e.Rrule = &r
		}
	}
	if e.RecurrenceID != nil {
		if e.OriginalStart == nil {
			return invalid("original_start is required for exception instances")
		}
		if e.Rrule != nil {
			return invalid("exception instances cannot carry an rrule")
		}
	}
	if e.Reminders == nil {
		e.Reminders = []int{}
	}
	for _, m := range e.Reminders {
		if m < 0 || m > 60*24*365 {
			return invalid("reminder minutes out of range")
		}
	}
	return nil
}

func remindersJSON(r []int) json.RawMessage {
	if r == nil {
		r = []int{}
	}
	b, _ := json.Marshal(r)
	return b
}

func upsertEventTx(ctx context.Context, q *db.Queries, userID string, e model.Event, existing *db.Event, now time.Time) (model.Event, error) {
	if err := validateEvent(ctx, q, userID, &e); err != nil {
		return model.Event{}, err
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Event{}, err
	}
	updated := e.UpdatedAt
	if updated.IsZero() {
		updated = now
	}
	if existing == nil {
		created := e.CreatedAt
		if created.IsZero() {
			created = now
		}
		err = q.InsertEvent(ctx, db.InsertEventParams{
			ID: e.ID, UserID: userID, CalendarID: e.CalendarID, Title: e.Title, Description: e.Description,
			Location: e.Location, StartAt: e.StartAt.UTC(), EndAt: e.EndAt.UTC(), Timezone: e.Timezone, AllDay: e.AllDay,
			Rrule: model.ToNullString(e.Rrule), RecurrenceID: model.ToNullString(e.RecurrenceID),
			OriginalStart: model.ToNullTime(e.OriginalStart), Reminders: remindersJSON(e.Reminders),
			CreatedAt: created.UTC(), UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: 1, ServerSeq: seq,
		})
	} else {
		err = q.UpdateEvent(ctx, db.UpdateEventParams{
			CalendarID: e.CalendarID, Title: e.Title, Description: e.Description, Location: e.Location,
			StartAt: e.StartAt.UTC(), EndAt: e.EndAt.UTC(), Timezone: e.Timezone, AllDay: e.AllDay,
			Rrule: model.ToNullString(e.Rrule), RecurrenceID: model.ToNullString(e.RecurrenceID),
			OriginalStart: model.ToNullTime(e.OriginalStart), Reminders: remindersJSON(e.Reminders),
			UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: existing.Version + 1, ServerSeq: seq,
			ID: e.ID, UserID: userID,
		})
	}
	if err != nil {
		return model.Event{}, err
	}
	row, err := q.GetEvent(ctx, db.GetEventParams{ID: e.ID, UserID: userID})
	if err != nil {
		return model.Event{}, err
	}
	return model.EventFromRow(row), nil
}

func deleteEventRowTx(ctx context.Context, q *db.Queries, userID string, existing db.Event, deletedAt time.Time) (model.Event, error) {
	if existing.DeletedAt.Valid {
		return model.EventFromRow(existing), nil
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Event{}, err
	}
	err = q.UpdateEvent(ctx, db.UpdateEventParams{
		CalendarID: existing.CalendarID, Title: existing.Title, Description: existing.Description, Location: existing.Location,
		StartAt: existing.StartAt, EndAt: existing.EndAt, Timezone: existing.Timezone, AllDay: existing.AllDay,
		Rrule: existing.Rrule, RecurrenceID: existing.RecurrenceID, OriginalStart: existing.OriginalStart,
		Reminders: existing.Reminders, UpdatedAt: deletedAt.UTC(),
		DeletedAt: sql.NullTime{Time: deletedAt.UTC(), Valid: true}, Version: existing.Version + 1, ServerSeq: seq,
		ID: existing.ID, UserID: userID,
	})
	if err != nil {
		return model.Event{}, err
	}
	row, err := q.GetEvent(ctx, db.GetEventParams{ID: existing.ID, UserID: userID})
	if err != nil {
		return model.Event{}, err
	}
	return model.EventFromRow(row), nil
}

// deleteEventTx soft-deletes an event; deleting a series master also deletes its exceptions.
func deleteEventTx(ctx context.Context, q *db.Queries, userID string, existing db.Event, deletedAt time.Time) (model.Event, error) {
	out, err := deleteEventRowTx(ctx, q, userID, existing, deletedAt)
	if err != nil {
		return out, err
	}
	if existing.Rrule.Valid {
		exceptions, err := q.ListEventExceptions(ctx, db.ListEventExceptionsParams{UserID: userID, SeriesIds: []sql.NullString{{String: existing.ID, Valid: true}}})
		if err != nil {
			return out, err
		}
		for _, ex := range exceptions {
			if _, err := deleteEventRowTx(ctx, q, userID, ex, deletedAt); err != nil {
				return out, err
			}
		}
	}
	return out, nil
}

func softDeleteEventsOfCalendar(ctx context.Context, q *db.Queries, userID, calendarID string, deletedAt time.Time) error {
	rows, err := q.ListEventsInRange(ctx, db.ListEventsInRangeParams{
		UserID: userID, RangeTo: time.Date(9999, 1, 1, 0, 0, 0, 0, time.UTC), RangeFrom: time.Time{},
	})
	if err != nil {
		return err
	}
	for _, r := range rows {
		if r.CalendarID != calendarID {
			continue
		}
		if _, err := deleteEventRowTx(ctx, q, userID, r, deletedAt); err != nil {
			return err
		}
	}
	return nil
}

// CreateEvent inserts an event via REST.
func (s *Store) CreateEvent(ctx context.Context, userID string, e model.Event) (out model.Event, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		if _, e2 := q.GetEventForUpdate(ctx, db.GetEventForUpdateParams{ID: e.ID, UserID: userID}); e2 == nil {
			return invalid("event %s already exists", e.ID)
		} else if !errors.Is(e2, sql.ErrNoRows) {
			return e2
		}
		e.UpdatedAt = time.Time{}
		out, err = upsertEventTx(ctx, q, userID, e, nil, s.Now())
		return err
	})
	return out, err
}

// UpdateEvent replaces an event via REST (optimistic check on version when > 0).
func (s *Store) UpdateEvent(ctx context.Context, userID string, e model.Event) (out model.Event, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		cur, e2 := q.GetEventForUpdate(ctx, db.GetEventForUpdateParams{ID: e.ID, UserID: userID})
		if errors.Is(e2, sql.ErrNoRows) || (e2 == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e2 != nil {
			return e2
		}
		if e.Version > 0 && e.Version != cur.Version {
			return &ErrConflict{Current: model.EventFromRow(cur)}
		}
		e.UpdatedAt = time.Time{}
		out, err = upsertEventTx(ctx, q, userID, e, &cur, s.Now())
		return err
	})
	return out, err
}

// DeleteEvent soft-deletes an event via REST.
func (s *Store) DeleteEvent(ctx context.Context, userID, id string) error {
	return s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetEventForUpdate(ctx, db.GetEventForUpdateParams{ID: id, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		_, err := deleteEventTx(ctx, q, userID, cur, s.Now())
		return err
	})
}

// GetEvent fetches a live event.
func (s *Store) GetEvent(ctx context.Context, userID, id string) (model.Event, error) {
	row, err := s.Queries().GetEvent(ctx, db.GetEventParams{ID: id, UserID: userID})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && row.DeletedAt.Valid) {
		return model.Event{}, ErrNotFound
	}
	if err != nil {
		return model.Event{}, err
	}
	return model.EventFromRow(row), nil
}

// ListEvents returns the events overlapping [from, to). Recurring masters are
// included whenever they start before `to` (the caller expands them).
func (s *Store) ListEvents(ctx context.Context, userID string, from, to time.Time) ([]model.Event, error) {
	rows, err := s.Queries().ListEventsInRange(ctx, db.ListEventsInRangeParams{UserID: userID, RangeTo: to.UTC(), RangeFrom: from.UTC()})
	if err != nil {
		return nil, err
	}
	out := make([]model.Event, 0, len(rows))
	for _, r := range rows {
		out = append(out, model.EventFromRow(r))
	}
	return out, nil
}

// ListExceptions returns live exception rows for the given series ids.
func (s *Store) ListExceptions(ctx context.Context, userID string, seriesIDs []string) ([]model.Event, error) {
	if len(seriesIDs) == 0 {
		return []model.Event{}, nil
	}
	ids := make([]sql.NullString, 0, len(seriesIDs))
	for _, id := range seriesIDs {
		ids = append(ids, sql.NullString{String: id, Valid: true})
	}
	rows, err := s.Queries().ListEventExceptions(ctx, db.ListEventExceptionsParams{UserID: userID, SeriesIds: ids})
	if err != nil {
		return nil, err
	}
	out := make([]model.Event, 0, len(rows))
	for _, r := range rows {
		out = append(out, model.EventFromRow(r))
	}
	return out, nil
}

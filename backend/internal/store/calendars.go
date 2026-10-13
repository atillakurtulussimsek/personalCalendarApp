package store

import (
	"context"
	"database/sql"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

var colorRe = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

func validateCalendar(c *model.Calendar) error {
	c.Name = strings.TrimSpace(c.Name)
	if c.Name == "" {
		return invalid("calendar name is required")
	}
	if len(c.Name) > 255 {
		return invalid("calendar name too long")
	}
	if c.Color == "" {
		c.Color = "#3B82F6"
	}
	if !colorRe.MatchString(c.Color) {
		return invalid("color must be #RRGGBB")
	}
	return nil
}

// upsertCalendarTx writes a calendar. If the row exists its version is bumped.
// The caller has already decided that the write should happen (conflicts resolved).
func upsertCalendarTx(ctx context.Context, q *db.Queries, userID string, c model.Calendar, existing *db.Calendar, now time.Time) (model.Calendar, error) {
	if err := validateCalendar(&c); err != nil {
		return model.Calendar{}, err
	}
	// There is always exactly one default calendar: the default can only move to
	// another calendar, never be switched off in place.
	if existing != nil && existing.IsDefault {
		c.IsDefault = true
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Calendar{}, err
	}
	if c.IsDefault {
		if err := q.ClearDefaultCalendar(ctx, db.ClearDefaultCalendarParams{UserID: userID, ID: c.ID}); err != nil {
			return model.Calendar{}, err
		}
	}
	if existing == nil {
		created := c.CreatedAt
		if created.IsZero() {
			created = now
		}
		updated := c.UpdatedAt
		if updated.IsZero() {
			updated = now
		}
		err = q.InsertCalendar(ctx, db.InsertCalendarParams{
			ID: c.ID, UserID: userID, Name: c.Name, Color: c.Color, IsDefault: c.IsDefault,
			CreatedAt: created.UTC(), UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: 1, ServerSeq: seq,
		})
		if err != nil {
			return model.Calendar{}, err
		}
	} else {
		updated := c.UpdatedAt
		if updated.IsZero() {
			updated = now
		}
		err = q.UpdateCalendar(ctx, db.UpdateCalendarParams{
			Name: c.Name, Color: c.Color, IsDefault: c.IsDefault, UpdatedAt: updated.UTC(),
			DeletedAt: sql.NullTime{}, Version: existing.Version + 1, ServerSeq: seq, ID: c.ID, UserID: userID,
		})
		if err != nil {
			return model.Calendar{}, err
		}
	}
	row, err := q.GetCalendar(ctx, db.GetCalendarParams{ID: c.ID, UserID: userID})
	if err != nil {
		return model.Calendar{}, err
	}
	return model.CalendarFromRow(row), nil
}

// deleteCalendarTx soft-deletes a calendar and every event inside it.
func deleteCalendarTx(ctx context.Context, q *db.Queries, userID string, existing db.Calendar, deletedAt time.Time) (model.Calendar, error) {
	if existing.DeletedAt.Valid {
		return model.CalendarFromRow(existing), nil
	}
	n, err := q.CountActiveCalendars(ctx, userID)
	if err != nil {
		return model.Calendar{}, err
	}
	if n <= 1 {
		return model.Calendar{}, invalid("cannot delete the last calendar")
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Calendar{}, err
	}
	err = q.UpdateCalendar(ctx, db.UpdateCalendarParams{
		Name: existing.Name, Color: existing.Color, IsDefault: false, UpdatedAt: deletedAt.UTC(),
		DeletedAt: sql.NullTime{Time: deletedAt.UTC(), Valid: true}, Version: existing.Version + 1, ServerSeq: seq,
		ID: existing.ID, UserID: userID,
	})
	if err != nil {
		return model.Calendar{}, err
	}
	if existing.IsDefault {
		if err := promoteDefaultCalendar(ctx, q, userID); err != nil {
			return model.Calendar{}, err
		}
	}
	if err := softDeleteEventsOfCalendar(ctx, q, userID, existing.ID, deletedAt); err != nil {
		return model.Calendar{}, err
	}
	row, err := q.GetCalendar(ctx, db.GetCalendarParams{ID: existing.ID, UserID: userID})
	if err != nil {
		return model.Calendar{}, err
	}
	return model.CalendarFromRow(row), nil
}

func promoteDefaultCalendar(ctx context.Context, q *db.Queries, userID string) error {
	list, err := q.ListCalendars(ctx, userID)
	if err != nil || len(list) == 0 {
		return err
	}
	first := list[0]
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return err
	}
	return q.UpdateCalendar(ctx, db.UpdateCalendarParams{
		Name: first.Name, Color: first.Color, IsDefault: true, UpdatedAt: first.UpdatedAt,
		DeletedAt: sql.NullTime{}, Version: first.Version + 1, ServerSeq: seq, ID: first.ID, UserID: userID,
	})
}

// CreateCalendar inserts a calendar via REST.
func (s *Store) CreateCalendar(ctx context.Context, userID string, c model.Calendar) (out model.Calendar, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		if _, e := q.GetCalendarForUpdate(ctx, db.GetCalendarForUpdateParams{ID: c.ID, UserID: userID}); e == nil {
			return invalid("calendar %s already exists", c.ID)
		} else if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		out, err = upsertCalendarTx(ctx, q, userID, c, nil, s.Now())
		return err
	})
	return out, err
}

// UpdateCalendar replaces a calendar via REST (optimistic check on version when > 0).
func (s *Store) UpdateCalendar(ctx context.Context, userID string, c model.Calendar) (out model.Calendar, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetCalendarForUpdate(ctx, db.GetCalendarForUpdateParams{ID: c.ID, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		if c.Version > 0 && c.Version != cur.Version {
			return &ErrConflict{Current: model.CalendarFromRow(cur)}
		}
		c.UpdatedAt = time.Time{}
		out, err = upsertCalendarTx(ctx, q, userID, c, &cur, s.Now())
		return err
	})
	return out, err
}

// DeleteCalendar soft-deletes a calendar via REST.
func (s *Store) DeleteCalendar(ctx context.Context, userID, id string) error {
	return s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetCalendarForUpdate(ctx, db.GetCalendarForUpdateParams{ID: id, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		_, err := deleteCalendarTx(ctx, q, userID, cur, s.Now())
		return err
	})
}

// GetCalendar fetches a live calendar.
func (s *Store) GetCalendar(ctx context.Context, userID, id string) (model.Calendar, error) {
	row, err := s.Queries().GetCalendar(ctx, db.GetCalendarParams{ID: id, UserID: userID})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && row.DeletedAt.Valid) {
		return model.Calendar{}, ErrNotFound
	}
	if err != nil {
		return model.Calendar{}, err
	}
	return model.CalendarFromRow(row), nil
}

// ListCalendars lists live calendars.
func (s *Store) ListCalendars(ctx context.Context, userID string) ([]model.Calendar, error) {
	rows, err := s.Queries().ListCalendars(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]model.Calendar, 0, len(rows))
	for _, r := range rows {
		out = append(out, model.CalendarFromRow(r))
	}
	return out, nil
}

// EnsureDefaultCalendar creates the "Takvim" default calendar for a new user.
func (s *Store) EnsureDefaultCalendar(ctx context.Context, userID, id string) error {
	return s.tx(ctx, func(q *db.Queries) error {
		n, err := q.CountActiveCalendars(ctx, userID)
		if err != nil || n > 0 {
			return err
		}
		_, err = upsertCalendarTx(ctx, q, userID, model.Calendar{ID: id, Name: "Takvim", Color: "#3B82F6", IsDefault: true}, nil, s.Now())
		return err
	})
}

// ErrConflict signals an optimistic-concurrency failure on a REST update.
type ErrConflict struct{ Current any }

func (e *ErrConflict) Error() string { return "version conflict" }

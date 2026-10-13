package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func validateTask(t *model.Task) error {
	t.Title = strings.TrimSpace(t.Title)
	if t.Title == "" {
		return invalid("task title is required")
	}
	if len(t.Title) > 512 {
		return invalid("task title too long")
	}
	return nil
}

func upsertTaskTx(ctx context.Context, q *db.Queries, userID string, t model.Task, existing *db.Task, now time.Time) (model.Task, error) {
	if err := validateTask(&t); err != nil {
		return model.Task{}, err
	}
	if t.NoteID != nil {
		n, err := q.GetNote(ctx, db.GetNoteParams{ID: *t.NoteID, UserID: userID})
		if errors.Is(err, sql.ErrNoRows) || (err == nil && n.DeletedAt.Valid) {
			t.NoteID = nil
		} else if err != nil {
			return model.Task{}, err
		}
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Task{}, err
	}
	updated := t.UpdatedAt
	if updated.IsZero() {
		updated = now
	}
	if existing == nil {
		created := t.CreatedAt
		if created.IsZero() {
			created = now
		}
		err = q.InsertTask(ctx, db.InsertTaskParams{
			ID: t.ID, UserID: userID, Title: t.Title, DueAt: model.ToNullTime(t.DueAt), Done: t.Done, NoteID: model.ToNullString(t.NoteID),
			CreatedAt: created.UTC(), UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: 1, ServerSeq: seq,
		})
	} else {
		err = q.UpdateTask(ctx, db.UpdateTaskParams{
			Title: t.Title, DueAt: model.ToNullTime(t.DueAt), Done: t.Done, NoteID: model.ToNullString(t.NoteID),
			UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: existing.Version + 1, ServerSeq: seq, ID: t.ID, UserID: userID,
		})
	}
	if err != nil {
		return model.Task{}, err
	}
	row, err := q.GetTask(ctx, db.GetTaskParams{ID: t.ID, UserID: userID})
	if err != nil {
		return model.Task{}, err
	}
	return model.TaskFromRow(row), nil
}

func deleteTaskTx(ctx context.Context, q *db.Queries, userID string, existing db.Task, deletedAt time.Time) (model.Task, error) {
	if existing.DeletedAt.Valid {
		return model.TaskFromRow(existing), nil
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Task{}, err
	}
	err = q.UpdateTask(ctx, db.UpdateTaskParams{
		Title: existing.Title, DueAt: existing.DueAt, Done: existing.Done, NoteID: existing.NoteID,
		UpdatedAt: deletedAt.UTC(), DeletedAt: sql.NullTime{Time: deletedAt.UTC(), Valid: true},
		Version: existing.Version + 1, ServerSeq: seq, ID: existing.ID, UserID: userID,
	})
	if err != nil {
		return model.Task{}, err
	}
	row, err := q.GetTask(ctx, db.GetTaskParams{ID: existing.ID, UserID: userID})
	if err != nil {
		return model.Task{}, err
	}
	return model.TaskFromRow(row), nil
}

// CreateTask inserts a task via REST.
func (s *Store) CreateTask(ctx context.Context, userID string, t model.Task) (out model.Task, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		if _, e := q.GetTaskForUpdate(ctx, db.GetTaskForUpdateParams{ID: t.ID, UserID: userID}); e == nil {
			return invalid("task %s already exists", t.ID)
		} else if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		t.UpdatedAt = time.Time{}
		out, err = upsertTaskTx(ctx, q, userID, t, nil, s.Now())
		return err
	})
	return out, err
}

// UpdateTask replaces a task via REST.
func (s *Store) UpdateTask(ctx context.Context, userID string, t model.Task) (out model.Task, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetTaskForUpdate(ctx, db.GetTaskForUpdateParams{ID: t.ID, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		if t.Version > 0 && t.Version != cur.Version {
			return &ErrConflict{Current: model.TaskFromRow(cur)}
		}
		t.UpdatedAt = time.Time{}
		out, err = upsertTaskTx(ctx, q, userID, t, &cur, s.Now())
		return err
	})
	return out, err
}

// DeleteTask soft-deletes a task via REST.
func (s *Store) DeleteTask(ctx context.Context, userID, id string) error {
	return s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetTaskForUpdate(ctx, db.GetTaskForUpdateParams{ID: id, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		_, err := deleteTaskTx(ctx, q, userID, cur, s.Now())
		return err
	})
}

// GetTask fetches a live task.
func (s *Store) GetTask(ctx context.Context, userID, id string) (model.Task, error) {
	row, err := s.Queries().GetTask(ctx, db.GetTaskParams{ID: id, UserID: userID})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && row.DeletedAt.Valid) {
		return model.Task{}, ErrNotFound
	}
	if err != nil {
		return model.Task{}, err
	}
	return model.TaskFromRow(row), nil
}

// ListTasks lists live tasks (open first, then by due date).
func (s *Store) ListTasks(ctx context.Context, userID string, limit, offset int32) ([]model.Task, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	rows, err := s.Queries().ListTasks(ctx, db.ListTasksParams{UserID: userID, Limit: limit, Offset: offset})
	if err != nil {
		return nil, err
	}
	out := make([]model.Task, 0, len(rows))
	for _, r := range rows {
		out = append(out, model.TaskFromRow(r))
	}
	return out, nil
}

func (s *Store) applyTask(ctx context.Context, q *db.Queries, userID string, it PushItem) (PushResult, error) {
	res := PushResult{Entity: it.Entity, ID: it.ID}
	cur, err := q.GetTaskForUpdate(ctx, db.GetTaskForUpdateParams{ID: it.ID, UserID: userID})
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
		res.Version, res.ServerSeq, res.Current = cur.Version, cur.ServerSeq, model.TaskFromRow(cur)
		return res, nil
	}
	var out model.Task
	if it.Op == OpDelete {
		out, err = deleteTaskTx(ctx, q, userID, cur, it.UpdatedAt)
	} else {
		var t model.Task
		if err := decodeData(it.Data, &t); err != nil {
			return res, err
		}
		t.ID, t.UpdatedAt = it.ID, it.UpdatedAt
		var existing *db.Task
		if exists {
			existing = &cur
		}
		out, err = upsertTaskTx(ctx, q, userID, t, existing, s.Now())
	}
	if err != nil {
		return res, err
	}
	res.Status, res.Version, res.ServerSeq = StatusApplied, out.Version, out.ServerSeq
	return res, nil
}

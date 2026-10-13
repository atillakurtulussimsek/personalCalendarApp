// Package store is the single write path for calendars, events and notes.
//
// Every mutation runs in a transaction, bumps the record version and allocates
// a new global server_seq from the sync_counter table. Both the REST CRUD
// handlers and POST /sync go through this package so the sync log is always
// consistent.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
)

// ErrNotFound is returned when a record does not exist for the user.
var ErrNotFound = errors.New("not found")

// ErrValidation wraps user input problems.
type ErrValidation struct{ Msg string }

func (e *ErrValidation) Error() string { return e.Msg }

func invalid(format string, a ...any) error {
	return &ErrValidation{Msg: fmt.Sprintf(format, a...)}
}

// Store wraps the database handle.
type Store struct {
	DB  *sql.DB
	Now func() time.Time
}

// New creates a Store using the real clock.
func New(sqlDB *sql.DB) *Store {
	return &Store{DB: sqlDB, Now: func() time.Time { return time.Now().UTC() }}
}

// Queries returns a non-transactional query handle.
func (s *Store) Queries() *db.Queries { return db.New(s.DB) }

// tx runs fn inside a transaction.
func (s *Store) tx(ctx context.Context, fn func(q *db.Queries) error) error {
	t, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	q := db.New(t)
	if err := fn(q); err != nil {
		_ = t.Rollback()
		return err
	}
	return t.Commit()
}

// nextSeq allocates the next global server_seq inside the current transaction.
func nextSeq(ctx context.Context, q *db.Queries) (int64, error) {
	res, err := q.NextServerSeq(ctx)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// LastSeq returns the current global sequence value.
func (s *Store) LastSeq(ctx context.Context) (int64, error) {
	return s.Queries().CurrentServerSeq(ctx)
}

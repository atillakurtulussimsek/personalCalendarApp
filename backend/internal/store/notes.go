package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

// ConflictCopyPrefix is prepended to the title of a note saved as a conflict copy.
const ConflictCopyPrefix = "(çakışan kopya) "

func validateNote(n *model.Note) error {
	n.Title = strings.TrimSpace(n.Title)
	if len(n.Title) > 512 {
		return invalid("note title too long")
	}
	if n.Title == "" && strings.TrimSpace(n.Body) == "" {
		return invalid("note needs a title or a body")
	}
	if n.Tags == nil {
		n.Tags = []string{}
	}
	clean := n.Tags[:0]
	seen := map[string]bool{}
	for _, t := range n.Tags {
		t = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(t, "#")))
		if t == "" || seen[t] {
			continue
		}
		if len(t) > 64 {
			return invalid("tag too long")
		}
		seen[t] = true
		clean = append(clean, t)
	}
	n.Tags = clean
	return nil
}

func tagsJSON(t []string) json.RawMessage {
	if t == nil {
		t = []string{}
	}
	b, _ := json.Marshal(t)
	return b
}

func upsertNoteTx(ctx context.Context, q *db.Queries, userID string, n model.Note, existing *db.Note, now time.Time) (model.Note, error) {
	if err := validateNote(&n); err != nil {
		return model.Note{}, err
	}
	if n.EventID != nil {
		ev, err := q.GetEvent(ctx, db.GetEventParams{ID: *n.EventID, UserID: userID})
		if errors.Is(err, sql.ErrNoRows) || (err == nil && ev.DeletedAt.Valid) {
			n.EventID = nil // dangling link: keep the note, drop the link
		} else if err != nil {
			return model.Note{}, err
		}
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Note{}, err
	}
	updated := n.UpdatedAt
	if updated.IsZero() {
		updated = now
	}
	if existing == nil {
		created := n.CreatedAt
		if created.IsZero() {
			created = now
		}
		err = q.InsertNote(ctx, db.InsertNoteParams{
			ID: n.ID, UserID: userID, Title: n.Title, Body: n.Body, Pinned: n.Pinned, EventID: model.ToNullString(n.EventID),
			Tags: tagsJSON(n.Tags), CreatedAt: created.UTC(), UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: 1, ServerSeq: seq,
		})
	} else {
		err = q.UpdateNote(ctx, db.UpdateNoteParams{
			Title: n.Title, Body: n.Body, Pinned: n.Pinned, EventID: model.ToNullString(n.EventID), Tags: tagsJSON(n.Tags),
			UpdatedAt: updated.UTC(), DeletedAt: sql.NullTime{}, Version: existing.Version + 1, ServerSeq: seq, ID: n.ID, UserID: userID,
		})
	}
	if err != nil {
		return model.Note{}, err
	}
	row, err := q.GetNote(ctx, db.GetNoteParams{ID: n.ID, UserID: userID})
	if err != nil {
		return model.Note{}, err
	}
	return model.NoteFromRow(row), nil
}

func deleteNoteTx(ctx context.Context, q *db.Queries, userID string, existing db.Note, deletedAt time.Time) (model.Note, error) {
	if existing.DeletedAt.Valid {
		return model.NoteFromRow(existing), nil
	}
	seq, err := nextSeq(ctx, q)
	if err != nil {
		return model.Note{}, err
	}
	err = q.UpdateNote(ctx, db.UpdateNoteParams{
		Title: existing.Title, Body: existing.Body, Pinned: existing.Pinned, EventID: existing.EventID, Tags: existing.Tags,
		UpdatedAt: deletedAt.UTC(), DeletedAt: sql.NullTime{Time: deletedAt.UTC(), Valid: true},
		Version: existing.Version + 1, ServerSeq: seq, ID: existing.ID, UserID: userID,
	})
	if err != nil {
		return model.Note{}, err
	}
	row, err := q.GetNote(ctx, db.GetNoteParams{ID: existing.ID, UserID: userID})
	if err != nil {
		return model.Note{}, err
	}
	return model.NoteFromRow(row), nil
}

// saveConflictCopyTx stores the losing version of a note as a separate note so no text is lost.
func saveConflictCopyTx(ctx context.Context, q *db.Queries, userID string, losing model.Note, now time.Time) (string, error) {
	copyNote := model.Note{
		ID:      uuid.NewString(),
		Title:   ConflictCopyPrefix + losing.Title,
		Body:    losing.Body,
		Pinned:  false,
		EventID: losing.EventID,
		Tags:    append([]string{}, losing.Tags...),
	}
	out, err := upsertNoteTx(ctx, q, userID, copyNote, nil, now)
	if err != nil {
		return "", err
	}
	return out.ID, nil
}

// CreateNote inserts a note via REST.
func (s *Store) CreateNote(ctx context.Context, userID string, n model.Note) (out model.Note, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		if _, e := q.GetNoteForUpdate(ctx, db.GetNoteForUpdateParams{ID: n.ID, UserID: userID}); e == nil {
			return invalid("note %s already exists", n.ID)
		} else if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		n.UpdatedAt = time.Time{}
		out, err = upsertNoteTx(ctx, q, userID, n, nil, s.Now())
		return err
	})
	return out, err
}

// UpdateNote replaces a note via REST (optimistic check on version when > 0).
func (s *Store) UpdateNote(ctx context.Context, userID string, n model.Note) (out model.Note, err error) {
	err = s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetNoteForUpdate(ctx, db.GetNoteForUpdateParams{ID: n.ID, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		if n.Version > 0 && n.Version != cur.Version {
			return &ErrConflict{Current: model.NoteFromRow(cur)}
		}
		n.UpdatedAt = time.Time{}
		out, err = upsertNoteTx(ctx, q, userID, n, &cur, s.Now())
		return err
	})
	return out, err
}

// DeleteNote soft-deletes a note via REST.
func (s *Store) DeleteNote(ctx context.Context, userID, id string) error {
	return s.tx(ctx, func(q *db.Queries) error {
		cur, e := q.GetNoteForUpdate(ctx, db.GetNoteForUpdateParams{ID: id, UserID: userID})
		if errors.Is(e, sql.ErrNoRows) || (e == nil && cur.DeletedAt.Valid) {
			return ErrNotFound
		} else if e != nil {
			return e
		}
		_, err := deleteNoteTx(ctx, q, userID, cur, s.Now())
		return err
	})
}

// GetNote fetches a live note.
func (s *Store) GetNote(ctx context.Context, userID, id string) (model.Note, error) {
	row, err := s.Queries().GetNote(ctx, db.GetNoteParams{ID: id, UserID: userID})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && row.DeletedAt.Valid) {
		return model.Note{}, ErrNotFound
	}
	if err != nil {
		return model.Note{}, err
	}
	return model.NoteFromRow(row), nil
}

// NoteFilter selects notes for listing.
type NoteFilter struct {
	Query   string
	Tag     string
	EventID string
	Limit   int32
	Offset  int32
}

// ListNotes lists live notes with optional full-text query, tag or event filter.
func (s *Store) ListNotes(ctx context.Context, userID string, f NoteFilter) ([]model.Note, error) {
	if f.Limit <= 0 || f.Limit > 500 {
		f.Limit = 100
	}
	q := s.Queries()
	var rows []db.Note
	var err error
	switch {
	case f.EventID != "":
		rows, err = q.ListNotesByEvent(ctx, db.ListNotesByEventParams{UserID: userID, EventID: sql.NullString{String: f.EventID, Valid: true}})
	case f.Query != "":
		rows, err = q.SearchNotes(ctx, db.SearchNotesParams{UserID: userID, Query: booleanQuery(f.Query), Limit: f.Limit, Offset: f.Offset})
	case f.Tag != "":
		rows, err = q.ListNotesByTag(ctx, db.ListNotesByTagParams{UserID: userID, Tag: strings.ToLower(strings.TrimSpace(f.Tag)), Limit: f.Limit, Offset: f.Offset})
	default:
		rows, err = q.ListNotes(ctx, db.ListNotesParams{UserID: userID, Limit: f.Limit, Offset: f.Offset})
	}
	if err != nil {
		return nil, err
	}
	out := make([]model.Note, 0, len(rows))
	for _, r := range rows {
		out = append(out, model.NoteFromRow(r))
	}
	return out, nil
}

// booleanQuery turns free text into a MySQL BOOLEAN MODE query: every word
// becomes a required prefix term; operator characters are stripped.
func booleanQuery(s string) string {
	var terms []string
	for _, w := range strings.Fields(s) {
		w = strings.Map(func(r rune) rune {
			if strings.ContainsRune(`+-><()~*"@`, r) {
				return -1
			}
			return r
		}, w)
		if w != "" {
			terms = append(terms, "+"+w+"*")
		}
	}
	return strings.Join(terms, " ")
}

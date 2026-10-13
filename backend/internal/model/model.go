// Package model holds the JSON-facing representations of domain records and
// conversions from the sqlc row types.
package model

import (
	"database/sql"
	"encoding/json"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
)

// Calendar is the API representation of a calendar.
type Calendar struct {
	ID        string     `json:"id"`
	Name      string     `json:"name"`
	Color     string     `json:"color"`
	IsDefault bool       `json:"is_default"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	DeletedAt *time.Time `json:"deleted_at"`
	Version   int64      `json:"version"`
	ServerSeq int64      `json:"server_seq"`
}

// Event is the API representation of an event (master or exception instance).
type Event struct {
	ID            string     `json:"id"`
	CalendarID    string     `json:"calendar_id"`
	Title         string     `json:"title"`
	Description   string     `json:"description"`
	Location      string     `json:"location"`
	StartAt       time.Time  `json:"start_at"`
	EndAt         time.Time  `json:"end_at"`
	Timezone      string     `json:"timezone"`
	AllDay        bool       `json:"all_day"`
	Rrule         *string    `json:"rrule"`
	RecurrenceID  *string    `json:"recurrence_id"`
	OriginalStart *time.Time `json:"original_start"`
	Reminders     []int      `json:"reminders"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	DeletedAt     *time.Time `json:"deleted_at"`
	Version       int64      `json:"version"`
	ServerSeq     int64      `json:"server_seq"`
}

// Occurrence is a single expanded instance of an event returned by expand=true.
type Occurrence struct {
	Event
	// OccurrenceStart/End are the concrete instance times; for exceptions they equal StartAt/EndAt.
	OccurrenceStart time.Time `json:"occurrence_start"`
	OccurrenceEnd   time.Time `json:"occurrence_end"`
	// SeriesID is the master event id (equals ID for non-recurring events).
	SeriesID string `json:"series_id"`
	// IsException is true when this instance comes from a stored exception row.
	IsException bool `json:"is_exception"`
}

// Note is the API representation of a note.
type Note struct {
	ID        string     `json:"id"`
	Title     string     `json:"title"`
	Body      string     `json:"body"`
	Pinned    bool       `json:"pinned"`
	EventID   *string    `json:"event_id"`
	Tags      []string   `json:"tags"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	DeletedAt *time.Time `json:"deleted_at"`
	Version   int64      `json:"version"`
	ServerSeq int64      `json:"server_seq"`
}

// Device is the API representation of a registered device.
type Device struct {
	ID         string     `json:"id"`
	Platform   string     `json:"platform"`
	Name       string     `json:"name"`
	PushToken  *string    `json:"push_token"`
	LastSyncAt *time.Time `json:"last_sync_at"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
	Version    int64      `json:"version"`
}

// User is the public user representation.
type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

// --- conversions -----------------------------------------------------------

func nullTime(t sql.NullTime) *time.Time {
	if !t.Valid {
		return nil
	}
	u := t.Time.UTC()
	return &u
}

func nullString(s sql.NullString) *string {
	if !s.Valid {
		return nil
	}
	v := s.String
	return &v
}

// ToNullTime converts a pointer to sql.NullTime (UTC).
func ToNullTime(t *time.Time) sql.NullTime {
	if t == nil {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: t.UTC(), Valid: true}
}

// ToNullString converts a pointer to sql.NullString.
func ToNullString(s *string) sql.NullString {
	if s == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *s, Valid: true}
}

// CalendarFromRow converts a sqlc row.
func CalendarFromRow(r db.Calendar) Calendar {
	return Calendar{
		ID: r.ID, Name: r.Name, Color: r.Color, IsDefault: r.IsDefault,
		CreatedAt: r.CreatedAt.UTC(), UpdatedAt: r.UpdatedAt.UTC(), DeletedAt: nullTime(r.DeletedAt),
		Version: r.Version, ServerSeq: r.ServerSeq,
	}
}

// EventFromRow converts a sqlc row.
func EventFromRow(r db.Event) Event {
	reminders := []int{}
	_ = json.Unmarshal(r.Reminders, &reminders)
	if reminders == nil {
		reminders = []int{}
	}
	return Event{
		ID: r.ID, CalendarID: r.CalendarID, Title: r.Title, Description: r.Description, Location: r.Location,
		StartAt: r.StartAt.UTC(), EndAt: r.EndAt.UTC(), Timezone: r.Timezone, AllDay: r.AllDay,
		Rrule: nullString(r.Rrule), RecurrenceID: nullString(r.RecurrenceID), OriginalStart: nullTime(r.OriginalStart),
		Reminders: reminders,
		CreatedAt: r.CreatedAt.UTC(), UpdatedAt: r.UpdatedAt.UTC(), DeletedAt: nullTime(r.DeletedAt),
		Version: r.Version, ServerSeq: r.ServerSeq,
	}
}

// NoteFromRow converts a sqlc row.
func NoteFromRow(r db.Note) Note {
	tags := []string{}
	_ = json.Unmarshal(r.Tags, &tags)
	if tags == nil {
		tags = []string{}
	}
	return Note{
		ID: r.ID, Title: r.Title, Body: r.Body, Pinned: r.Pinned, EventID: nullString(r.EventID), Tags: tags,
		CreatedAt: r.CreatedAt.UTC(), UpdatedAt: r.UpdatedAt.UTC(), DeletedAt: nullTime(r.DeletedAt),
		Version: r.Version, ServerSeq: r.ServerSeq,
	}
}

// DeviceFromRow converts a sqlc row.
func DeviceFromRow(r db.Device) Device {
	return Device{
		ID: r.ID, Platform: r.Platform, Name: r.Name, PushToken: nullString(r.PushToken),
		LastSyncAt: nullTime(r.LastSyncAt), CreatedAt: r.CreatedAt.UTC(), UpdatedAt: r.UpdatedAt.UTC(),
		Version: r.Version,
	}
}

// UserFromRow converts a sqlc row.
func UserFromRow(r db.User) User {
	return User{ID: r.ID, Email: r.Email, CreatedAt: r.CreatedAt.UTC()}
}

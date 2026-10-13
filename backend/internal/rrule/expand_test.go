package rrule

import (
	"testing"
	"time"

	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func str(s string) *string      { return &s }
func ts(t time.Time) *time.Time { return &t }

func TestExpandWeeklyAcrossDST(t *testing.T) {
	ist, _ := time.LoadLocation("Europe/Istanbul")
	// Turkey has no DST since 2016 (permanent UTC+3); use Europe/Berlin to exercise a DST change.
	ber, _ := time.LoadLocation("Europe/Berlin")
	_ = ist
	start := time.Date(2026, 3, 23, 9, 0, 0, 0, ber) // Monday 09:00 CET (UTC+1)
	ev := model.Event{ID: "m", Title: "weekly", StartAt: start.UTC(), EndAt: start.Add(time.Hour).UTC(),
		Timezone: "Europe/Berlin", Rrule: str("FREQ=WEEKLY;BYDAY=MO;COUNT=3")}
	from := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
	occ, err := Expand([]model.Event{ev}, nil, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if len(occ) != 3 {
		t.Fatalf("want 3 occurrences, got %d", len(occ))
	}
	// 2026-03-30 is after the DST switch (29 March): local 09:00 must be kept → 07:00 UTC.
	if got := occ[1].OccurrenceStart; !got.Equal(time.Date(2026, 3, 30, 7, 0, 0, 0, time.UTC)) {
		t.Fatalf("DST occurrence wrong: %v", got)
	}
	if occ[0].OccurrenceStart.In(ber).Hour() != 9 || occ[2].OccurrenceStart.In(ber).Hour() != 9 {
		t.Fatal("local hour drifted")
	}
}

func TestExpandExceptions(t *testing.T) {
	start := time.Date(2026, 1, 5, 10, 0, 0, 0, time.UTC)
	master := model.Event{ID: "m", Title: "daily", StartAt: start, EndAt: start.Add(30 * time.Minute),
		Timezone: "UTC", Rrule: str("FREQ=DAILY;COUNT=5")}
	// 2nd occurrence moved to 15:00; 3rd occurrence deleted
	moved := model.Event{ID: "x1", Title: "moved", RecurrenceID: str("m"), OriginalStart: ts(start.AddDate(0, 0, 1)),
		StartAt: start.AddDate(0, 0, 1).Add(5 * time.Hour), EndAt: start.AddDate(0, 0, 1).Add(5*time.Hour + 30*time.Minute), Timezone: "UTC"}
	del := time.Now()
	removed := model.Event{ID: "x2", RecurrenceID: str("m"), OriginalStart: ts(start.AddDate(0, 0, 2)),
		StartAt: start.AddDate(0, 0, 2), EndAt: start.AddDate(0, 0, 2).Add(30 * time.Minute), Timezone: "UTC", DeletedAt: &del}
	occ, err := Expand([]model.Event{master}, []model.Event{moved, removed}, start.AddDate(0, 0, -1), start.AddDate(0, 0, 10))
	if err != nil {
		t.Fatal(err)
	}
	if len(occ) != 4 {
		t.Fatalf("want 4 occurrences (5 - 1 deleted), got %d", len(occ))
	}
	if occ[1].ID != "x1" || !occ[1].IsException || occ[1].OccurrenceStart.Hour() != 15 {
		t.Fatalf("exception not applied: %+v", occ[1])
	}
	for _, o := range occ {
		if o.OccurrenceStart.Equal(start.AddDate(0, 0, 2)) {
			t.Fatal("deleted occurrence still present")
		}
	}
}

func TestExpandWindowEdges(t *testing.T) {
	start := time.Date(2026, 1, 1, 23, 0, 0, 0, time.UTC)
	ev := model.Event{ID: "m", StartAt: start, EndAt: start.Add(2 * time.Hour), Timezone: "UTC", Rrule: str("FREQ=DAILY;COUNT=2")}
	// window starts at 00:00 on the 2nd: first occurrence (23:00–01:00) overlaps and must be included
	from := time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 1, 2, 12, 0, 0, 0, time.UTC)
	occ, err := Expand([]model.Event{ev}, nil, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if len(occ) != 1 || !occ[0].OccurrenceStart.Equal(start) {
		t.Fatalf("overlap at window start missed: %+v", occ)
	}
	plain := model.Event{ID: "p", StartAt: from, EndAt: from.Add(time.Hour), Timezone: "UTC"}
	occ, _ = Expand([]model.Event{plain}, nil, from.Add(time.Hour), to)
	if len(occ) != 0 {
		t.Fatal("event ending exactly at window start must be excluded")
	}
}

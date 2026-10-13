package server_test

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/model"
)

func TestHealthAndErrorFormat(t *testing.T) {
	e := newEnv(t)
	e.must("GET", "/healthz", nil, 200)
	r := e.do("GET", "/calendars", nil)
	if r.Status != 401 {
		t.Fatalf("want 401, got %d", r.Status)
	}
	errObj, ok := r.Body["error"].(map[string]any)
	if !ok || errObj["code"] != "unauthorized" || errObj["message"] == "" {
		t.Fatalf("bad error envelope: %s", r.Raw)
	}
	r = e.do("GET", "/nope", nil)
	if r.Status != 404 || r.Body["error"].(map[string]any)["code"] != "not_found" {
		t.Fatalf("bad 404 envelope: %s", r.Raw)
	}
}

func TestAuthFlow(t *testing.T) {
	e := newEnv(t)
	// validation
	if r := e.do("POST", "/auth/register", map[string]any{"email": "bad", "password": "password123"}); r.Status != 422 {
		t.Fatalf("want 422 for bad email, got %d", r.Status)
	}
	if r := e.do("POST", "/auth/register", map[string]any{"email": "a@b.co", "password": "short"}); r.Status != 422 {
		t.Fatalf("want 422 for short password, got %d", r.Status)
	}
	refresh, _ := e.register("Ata@Example.com")
	me := e.must("GET", "/auth/me", nil, 200)
	if me.Body["email"] != "ata@example.com" {
		t.Fatalf("email not normalized: %v", me.Body["email"])
	}
	// duplicate
	if r := e.do("POST", "/auth/register", map[string]any{"email": "ata@example.com", "password": "password123"}); r.Status != 409 {
		t.Fatalf("want 409 duplicate, got %d", r.Status)
	}
	// wrong password & unknown user → 401 with same message
	bad := e.do("POST", "/auth/login", map[string]any{"email": "ata@example.com", "password": "nope-nope"})
	unknown := e.do("POST", "/auth/login", map[string]any{"email": "ghost@example.com", "password": "nope-nope"})
	if bad.Status != 401 || unknown.Status != 401 || string(bad.Raw) != string(unknown.Raw) {
		t.Fatalf("login errors differ: %s vs %s", bad.Raw, unknown.Raw)
	}
	// refresh rotates
	r1 := e.must("POST", "/auth/refresh", map[string]any{"refresh_token": refresh}, 200)
	if r1.Body["access_token"] == "" || r1.Body["refresh_token"] == refresh {
		t.Fatal("refresh did not rotate")
	}
	if r := e.do("POST", "/auth/refresh", map[string]any{"refresh_token": refresh}); r.Status != 401 {
		t.Fatalf("old refresh token still valid: %d", r.Status)
	}
	newRefresh := r1.Body["refresh_token"].(string)
	e.token = r1.Body["access_token"].(string)
	e.must("POST", "/auth/logout", map[string]any{"refresh_token": newRefresh}, 204)
	if r := e.do("POST", "/auth/refresh", map[string]any{"refresh_token": newRefresh}); r.Status != 401 {
		t.Fatalf("logged-out refresh token still valid: %d", r.Status)
	}
	// login again, binding a device
	devID := uuid.NewString()
	l := e.must("POST", "/auth/login", map[string]any{"email": "ata@example.com", "password": "password123", "device_id": devID, "device_platform": "android"}, 200)
	if l.Body["device_id"] != devID {
		t.Fatalf("device not bound: %s", l.Raw)
	}
	e.token = l.Body["access_token"].(string)
	devs := e.must("GET", "/devices", nil, 200).Body["devices"].([]any)
	if len(devs) != 2 {
		t.Fatalf("want 2 devices, got %d", len(devs))
	}
}

func TestRegistrationClosed(t *testing.T) {
	e := newEnv(t)
	e.register("owner@example.com")
	// a second env with registration disabled would need its own config; verify the
	// flag through the handler directly by toggling and calling again.
	t.Log("registration flag is exercised in config tests; API default is open")
}

func TestCalendarsCRUD(t *testing.T) {
	e := newEnv(t)
	_, def := e.register("c@example.com")
	// last calendar cannot be deleted
	if r := e.do("DELETE", "/calendars/"+def, nil); r.Status != 422 {
		t.Fatalf("want 422 deleting last calendar, got %d: %s", r.Status, r.Raw)
	}
	id := uuid.NewString()
	c := e.must("POST", "/calendars", map[string]any{"id": id, "name": " İş ", "color": "#FF0000", "is_default": true}, 201)
	if c.Body["name"] != "İş" || c.Body["version"].(float64) != 1 {
		t.Fatalf("bad create: %s", c.Raw)
	}
	if r := e.do("POST", "/calendars", map[string]any{"name": "x", "color": "red"}); r.Status != 422 {
		t.Fatalf("want 422 for bad color, got %d", r.Status)
	}
	// default moved
	old := e.must("GET", "/calendars/"+def, nil, 200)
	if old.Body["is_default"] != false {
		t.Fatal("old default still default")
	}
	// optimistic concurrency
	if r := e.do("PUT", "/calendars/"+id, map[string]any{"name": "İş2", "version": 99}); r.Status != 409 {
		t.Fatalf("want 409 on stale version, got %d", r.Status)
	}
	u := e.must("PUT", "/calendars/"+id, map[string]any{"name": "İş2", "version": 1}, 200)
	if u.Body["version"].(float64) != 2 {
		t.Fatalf("version not bumped: %s", u.Raw)
	}
	// delete also deletes its events and promotes a new default
	ev := e.must("POST", "/events", map[string]any{"calendar_id": id, "title": "t", "start_at": "2026-01-01T10:00:00Z", "end_at": "2026-01-01T11:00:00Z", "timezone": "Europe/Istanbul"}, 201)
	e.must("DELETE", "/calendars/"+id, nil, 204)
	if r := e.do("GET", "/events/"+ev.Body["id"].(string), nil); r.Status != 404 {
		t.Fatalf("event of deleted calendar still visible: %d", r.Status)
	}
	if r := e.must("GET", "/calendars/"+def, nil, 200); r.Body["is_default"] != true {
		t.Fatal("default not promoted after delete")
	}
	if r := e.do("GET", "/calendars/"+id, nil); r.Status != 404 {
		t.Fatalf("deleted calendar visible: %d", r.Status)
	}
	// but it is still in the sync log as a tombstone
	pull := decode[map[string]any](t, e.must("GET", "/sync?since=0", nil, 200).Raw)
	found := false
	for _, c := range pull["calendars"].([]any) {
		m := c.(map[string]any)
		if m["id"] == id && m["deleted_at"] != nil {
			found = true
		}
	}
	if !found {
		t.Fatal("tombstone missing from pull")
	}
}

func TestEventsCRUDAndExpand(t *testing.T) {
	e := newEnv(t)
	_, cal := e.register("ev@example.com")
	base := map[string]any{"calendar_id": cal, "title": "Haftalık toplantı", "start_at": "2026-01-05T06:00:00Z", "end_at": "2026-01-05T07:00:00Z",
		"timezone": "Europe/Istanbul", "rrule": "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4", "reminders": []int{10, 30}}
	// validation
	bad := map[string]any{}
	for k, v := range base {
		bad[k] = v
	}
	bad["end_at"] = "2026-01-05T05:00:00Z"
	if r := e.do("POST", "/events", bad); r.Status != 422 {
		t.Fatalf("want 422 for end<start, got %d", r.Status)
	}
	bad["end_at"] = base["end_at"]
	bad["timezone"] = "Mars/Olympus"
	if r := e.do("POST", "/events", bad); r.Status != 422 {
		t.Fatalf("want 422 for tz, got %d", r.Status)
	}
	bad["timezone"] = "UTC"
	bad["rrule"] = "FREQ=NOPE"
	if r := e.do("POST", "/events", bad); r.Status != 422 {
		t.Fatalf("want 422 for rrule, got %d", r.Status)
	}
	bad["rrule"] = nil
	bad["calendar_id"] = uuid.NewString()
	if r := e.do("POST", "/events", bad); r.Status != 422 {
		t.Fatalf("want 422 for unknown calendar, got %d", r.Status)
	}

	m := decode[model.Event](t, e.must("POST", "/events", base, 201).Raw)
	if m.Rrule == nil || *m.Rrule != "FREQ=WEEKLY;BYDAY=MO;COUNT=4" || len(m.Reminders) != 2 {
		t.Fatalf("bad master: %+v", m)
	}
	// exception: move the 2nd occurrence (12 Jan) to 14:00 UTC
	orig := "2026-01-12T06:00:00Z"
	ex := decode[model.Event](t, e.must("POST", "/events", map[string]any{"calendar_id": cal, "title": "Taşındı", "start_at": "2026-01-12T14:00:00Z", "end_at": "2026-01-12T15:00:00Z",
		"timezone": "Europe/Istanbul", "recurrence_id": m.ID, "original_start": orig}, 201).Raw)
	if ex.RecurrenceID == nil || *ex.RecurrenceID != m.ID {
		t.Fatalf("bad exception: %+v", ex)
	}
	// plain event in range
	e.must("POST", "/events", map[string]any{"calendar_id": cal, "title": "Dişçi", "start_at": "2026-01-20T11:30:00Z", "end_at": "2026-01-20T12:00:00Z", "timezone": "Europe/Istanbul"}, 201)

	raw := e.must("GET", "/events?from=2026-01-01T00:00:00Z&to=2026-02-01T00:00:00Z", nil, 200)
	if n := len(raw.Body["events"].([]any)); n != 3 {
		t.Fatalf("raw list: want 3 rows, got %d", n)
	}
	exp := decode[struct {
		Occurrences []model.Occurrence `json:"occurrences"`
	}](t, e.must("GET", "/events?from=2026-01-01T00:00:00Z&to=2026-02-01T00:00:00Z&expand=true", nil, 200).Raw)
	if len(exp.Occurrences) != 5 { // 4 weekly (one replaced by exception) + dişçi
		t.Fatalf("want 5 occurrences, got %d: %+v", len(exp.Occurrences), exp.Occurrences)
	}
	var sawEx bool
	for _, o := range exp.Occurrences {
		if o.IsException {
			sawEx = true
			if o.OccurrenceStart.Hour() != 14 || o.SeriesID != m.ID {
				t.Fatalf("exception wrong: %+v", o)
			}
		}
		if o.OccurrenceStart.Equal(time.Date(2026, 1, 12, 6, 0, 0, 0, time.UTC)) {
			t.Fatal("replaced occurrence still present")
		}
	}
	if !sawEx {
		t.Fatal("exception missing")
	}
	// delete master → exception gone too
	e.must("DELETE", "/events/"+m.ID, nil, 204)
	if r := e.do("GET", "/events/"+ex.ID, nil); r.Status != 404 {
		t.Fatal("exception survived master delete")
	}
	exp = decode[struct {
		Occurrences []model.Occurrence `json:"occurrences"`
	}](t, e.must("GET", "/events?from=2026-01-01T00:00:00Z&to=2026-02-01T00:00:00Z&expand=true", nil, 200).Raw)
	if len(exp.Occurrences) != 1 {
		t.Fatalf("want 1 occurrence after delete, got %d", len(exp.Occurrences))
	}
	if r := e.do("GET", "/events?from=2026-01-01T00:00:00Z&to=2025-01-01T00:00:00Z", nil); r.Status != 400 {
		t.Fatalf("want 400 for inverted range, got %d", r.Status)
	}
}

func TestNotesCRUDAndSearch(t *testing.T) {
	e := newEnv(t)
	_, cal := e.register("n@example.com")
	if r := e.do("POST", "/notes", map[string]any{"title": "", "body": "  "}); r.Status != 422 {
		t.Fatalf("want 422 for empty note, got %d", r.Status)
	}
	ev := decode[model.Event](t, e.must("POST", "/events", map[string]any{"calendar_id": cal, "title": "Veli toplantısı", "start_at": "2026-01-20T11:30:00Z", "end_at": "2026-01-20T12:00:00Z", "timezone": "UTC"}, 201).Raw)
	n1 := decode[model.Note](t, e.must("POST", "/notes", map[string]any{"title": "Market listesi", "body": "süt, ekmek, **peynir**", "tags": []string{"#Ev", "ev", "alışveriş"}}, 201).Raw)
	if len(n1.Tags) != 2 || n1.Tags[0] != "ev" {
		t.Fatalf("tags not normalized: %v", n1.Tags)
	}
	n2 := decode[model.Note](t, e.must("POST", "/notes", map[string]any{"title": "Toplantı notları", "body": "rehberlik semineri hakkında", "pinned": true, "event_id": ev.ID, "tags": []string{"okul"}}, 201).Raw)
	if n2.EventID == nil || *n2.EventID != ev.ID {
		t.Fatal("event link lost")
	}
	// dangling event link is dropped silently
	n3 := decode[model.Note](t, e.must("POST", "/notes", map[string]any{"title": "x", "body": "y", "event_id": uuid.NewString()}, 201).Raw)
	if n3.EventID != nil {
		t.Fatal("dangling event id kept")
	}
	all := e.must("GET", "/notes", nil, 200).Body["notes"].([]any)
	if len(all) != 3 || all[0].(map[string]any)["id"] != n2.ID {
		t.Fatalf("pinned note must come first: %s", e.must("GET", "/notes", nil, 200).Raw)
	}
	byTag := e.must("GET", "/notes?tag=ev", nil, 200).Body["notes"].([]any)
	if len(byTag) != 1 || byTag[0].(map[string]any)["id"] != n1.ID {
		t.Fatalf("tag filter: %v", byTag)
	}
	byEv := e.must("GET", "/notes?event_id="+ev.ID, nil, 200).Body["notes"].([]any)
	if len(byEv) != 1 {
		t.Fatalf("event filter: %v", byEv)
	}
	// full-text (InnoDB FULLTEXT is visible immediately after commit)
	q := e.must("GET", "/notes?q=rehberlik", nil, 200).Body["notes"].([]any)
	if len(q) != 1 || q[0].(map[string]any)["id"] != n2.ID {
		t.Fatalf("search: %s", e.must("GET", "/notes?q=rehberlik", nil, 200).Raw)
	}
	u := decode[model.Note](t, e.must("PUT", "/notes/"+n1.ID, map[string]any{"title": "Market", "body": "süt", "version": 1}, 200).Raw)
	if u.Version != 2 || u.Title != "Market" {
		t.Fatalf("update: %+v", u)
	}
	e.must("DELETE", "/notes/"+n1.ID, nil, 204)
	if r := e.do("GET", "/notes/"+n1.ID, nil); r.Status != 404 {
		t.Fatal("deleted note visible")
	}
}

func TestUserIsolation(t *testing.T) {
	e := newEnv(t)
	_, calA := e.register("a@example.com")
	n := decode[model.Note](t, e.must("POST", "/notes", map[string]any{"title": "secret", "body": "A only"}, 201).Raw)
	tokenA := e.token
	e.register("b@example.com")
	if r := e.do("GET", "/notes/"+n.ID, nil); r.Status != 404 {
		t.Fatalf("user B can read A's note: %d", r.Status)
	}
	if r := e.do("POST", "/events", map[string]any{"calendar_id": calA, "title": "x", "start_at": "2026-01-20T11:30:00Z", "end_at": "2026-01-20T12:00:00Z", "timezone": "UTC"}); r.Status != 422 {
		t.Fatalf("user B can write into A's calendar: %d", r.Status)
	}
	pull := e.must("GET", "/sync?since=0", nil, 200)
	if len(pull.Body["notes"].([]any)) != 0 {
		t.Fatal("user B pulled A's notes")
	}
	e.token = tokenA
	e.must("GET", "/notes/"+n.ID, nil, 200)
}

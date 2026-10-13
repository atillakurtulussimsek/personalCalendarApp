package server_test

import (
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/model"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

func TestTasksCRUDAndSync(t *testing.T) {
	e := newEnv(t)
	e.register("t@example.com")
	if r := e.do("POST", "/tasks", map[string]any{"title": "  "}); r.Status != 422 {
		t.Fatalf("want 422 for empty title, got %d", r.Status)
	}
	n := decode[model.Note](t, e.must("POST", "/notes", map[string]any{"title": "n", "body": "b"}, 201).Raw)
	tk := decode[model.Task](t, e.must("POST", "/tasks", map[string]any{"title": "Rapor yaz", "due_at": "2026-03-01T09:00:00Z", "note_id": n.ID}, 201).Raw)
	if tk.NoteID == nil || *tk.NoteID != n.ID || tk.DueAt == nil {
		t.Fatalf("bad task %+v", tk)
	}
	// dangling note link dropped
	tk2 := decode[model.Task](t, e.must("POST", "/tasks", map[string]any{"title": "x", "note_id": uuid.NewString()}, 201).Raw)
	if tk2.NoteID != nil {
		t.Fatal("dangling note kept")
	}
	done := decode[model.Task](t, e.must("PUT", "/tasks/"+tk.ID, map[string]any{"title": "Rapor yaz", "done": true, "version": 1}, 200).Raw)
	if !done.Done || done.Version != 2 {
		t.Fatalf("update: %+v", done)
	}
	list := e.must("GET", "/tasks", nil, 200).Body["tasks"].([]any)
	if len(list) != 2 || list[0].(map[string]any)["id"] != tk2.ID { // open task first
		t.Fatalf("order: %v", list)
	}
	// sync: push + pull include tasks
	id := uuid.NewString()
	res := e.push(item("task", "upsert", id, 0, time.Now().UTC(), model.Task{Title: "Sync görevi"}))
	if res.Results[0].Status != store.StatusApplied {
		t.Fatalf("push task: %+v", res.Results[0])
	}
	p := e.pull(0)
	if len(p.Tasks) != 3 {
		t.Fatalf("pull tasks: %d", len(p.Tasks))
	}
	e.must("DELETE", "/tasks/"+tk.ID, nil, 204)
	if r := e.do("GET", "/tasks/"+tk.ID, nil); r.Status != 404 {
		t.Fatal("deleted task visible")
	}
}

func TestExportICS(t *testing.T) {
	e := newEnv(t)
	_, cal := e.register("ics@example.com")
	e.must("POST", "/events", map[string]any{"calendar_id": cal, "title": "Haftalık, toplantı", "start_at": "2026-01-05T06:00:00Z", "end_at": "2026-01-05T07:00:00Z",
		"timezone": "Europe/Istanbul", "rrule": "FREQ=WEEKLY;BYDAY=MO", "reminders": []int{10}, "location": "Salon A"}, 201)
	e.must("POST", "/events", map[string]any{"calendar_id": cal, "title": "Tatil", "all_day": true, "start_at": "2026-04-23T00:00:00Z", "end_at": "2026-04-24T00:00:00Z", "timezone": "UTC"}, 201)
	r := e.must("GET", "/calendars/"+cal+"/export.ics", nil, 200)
	body := string(r.Raw)
	for _, want := range []string{"BEGIN:VCALENDAR", "RRULE:FREQ=WEEKLY;BYDAY=MO", "SUMMARY:Haftalık\\, toplantı", "DTSTART;VALUE=DATE:20260423", "TRIGGER:-PT10M", "LOCATION:Salon A", "END:VCALENDAR"} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in\n%s", want, body)
		}
	}
	all := e.must("GET", "/export.ics", nil, 200)
	if strings.Count(string(all.Raw), "BEGIN:VEVENT") != 2 {
		t.Fatalf("expected 2 events in full export")
	}
	if r := e.do("GET", "/calendars/"+uuid.NewString()+"/export.ics", nil); r.Status != 404 {
		t.Fatalf("want 404 for unknown calendar, got %d", r.Status)
	}
}

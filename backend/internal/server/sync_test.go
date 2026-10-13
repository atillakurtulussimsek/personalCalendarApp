package server_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/atillasimsek/personal-calendar/backend/internal/model"
	"github.com/atillasimsek/personal-calendar/backend/internal/store"
)

func item(entity, op, id string, base int64, at time.Time, data any) store.PushItem {
	var raw json.RawMessage
	if data != nil {
		raw, _ = json.Marshal(data)
	}
	return store.PushItem{Entity: entity, Op: op, ID: id, BaseVersion: base, UpdatedAt: at, Data: raw}
}

func (e *testEnv) push(items ...store.PushItem) store.PushResponse {
	e.t.Helper()
	r := e.must("POST", "/sync", map[string]any{"items": items}, 200)
	return decode[store.PushResponse](e.t, r.Raw)
}

func (e *testEnv) pull(since int64) store.PullResponse {
	e.t.Helper()
	return decode[store.PullResponse](e.t, e.must("GET", "/sync?since="+itoa(since), nil, 200).Raw)
}

func itoa(n int64) string { return formatInt(n) }

func formatInt(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	if neg {
		b = append([]byte{'-'}, b...)
	}
	return string(b)
}

// TestSyncOfflineScenario: a client creates, edits and deletes while offline,
// then pushes its outbox in one batch; a second device pulls everything.
func TestSyncOfflineScenario(t *testing.T) {
	e := newEnv(t)
	_, cal := e.register("sync@example.com")
	t0 := time.Date(2026, 2, 1, 9, 0, 0, 0, time.UTC)
	noteID, evID, cal2ID := uuid.NewString(), uuid.NewString(), uuid.NewString()

	// --- device A outbox (collapsed per record as a real client would do, except the delete which is kept) ---
	res := e.push(
		item("calendar", "upsert", cal2ID, 0, t0, model.Calendar{Name: "Okul", Color: "#00AA00"}),
		item("note", "upsert", noteID, 0, t0.Add(time.Minute), model.Note{Title: "Fikir", Body: "ilk sürüm", Tags: []string{"fikir"}}),
		item("event", "upsert", evID, 0, t0.Add(2*time.Minute), model.Event{CalendarID: cal2ID, Title: "Seminer", StartAt: t0.AddDate(0, 0, 3), EndAt: t0.AddDate(0, 0, 3).Add(time.Hour), Timezone: "Europe/Istanbul", Location: "Konferans salonu"}),
		item("note", "upsert", noteID, 1, t0.Add(3*time.Minute), model.Note{Title: "Fikir", Body: "düzenlenmiş sürüm", Tags: []string{"fikir"}}),
		item("event", "delete", evID, 1, t0.Add(4*time.Minute), nil),
		item("event", "delete", uuid.NewString(), 0, t0, nil),                            // created+deleted offline, never seen by server
		item("note", "upsert", uuid.NewString(), 0, t0, model.Note{Title: "", Body: ""}), // invalid
		item("widget", "upsert", uuid.NewString(), 0, t0, nil),                           // unknown entity
	)
	want := []string{"applied", "applied", "applied", "applied", "applied", "ignored", "rejected", "rejected"}
	for i, w := range want {
		if res.Results[i].Status != w {
			t.Fatalf("item %d: status %s want %s (%s)", i, res.Results[i].Status, w, res.Results[i].Error)
		}
	}
	if res.Results[3].Version != 2 || res.Results[4].Version != 2 {
		t.Fatalf("versions: %+v", res.Results)
	}
	if res.LastSeq == 0 {
		t.Fatal("last_seq missing")
	}

	// --- device B full pull ---
	p := e.pull(0)
	if len(p.Calendars) != 2 || len(p.Notes) != 1 || len(p.Events) != 1 {
		t.Fatalf("pull counts: cal=%d notes=%d events=%d", len(p.Calendars), len(p.Notes), len(p.Events))
	}
	if p.Notes[0].Body != "düzenlenmiş sürüm" || p.Notes[0].Version != 2 {
		t.Fatalf("note not updated: %+v", p.Notes[0])
	}
	if p.Events[0].DeletedAt == nil {
		t.Fatal("event tombstone missing")
	}
	if p.LastSeq != res.LastSeq || p.HasMore {
		t.Fatalf("seq mismatch: pull=%d push=%d has_more=%v", p.LastSeq, res.LastSeq, p.HasMore)
	}
	// incremental pull is empty
	p2 := e.pull(p.LastSeq)
	if len(p2.Calendars)+len(p2.Notes)+len(p2.Events) != 0 {
		t.Fatal("incremental pull returned stale rows")
	}
	// REST write shows up in the next incremental pull
	e.must("PUT", "/notes/"+noteID, map[string]any{"title": "Fikir", "body": "REST sürümü", "version": 2}, 200)
	p3 := e.pull(p.LastSeq)
	if len(p3.Notes) != 1 || p3.Notes[0].Body != "REST sürümü" || p3.Notes[0].Version != 3 {
		t.Fatalf("REST change not in pull: %+v", p3.Notes)
	}
	_ = cal
}

func TestSyncConflicts(t *testing.T) {
	e := newEnv(t)
	e.register("conf@example.com")
	t0 := time.Date(2026, 2, 1, 9, 0, 0, 0, time.UTC)
	id := uuid.NewString()
	e.push(item("note", "upsert", id, 0, t0, model.Note{Title: "N", Body: "v1"}))
	// server moves on: v2 at t0+10m (via REST, server clock)
	*e.Clock = t0.Add(10 * time.Minute)
	e.must("PUT", "/notes/"+id, map[string]any{"title": "N", "body": "server v2", "version": 1}, 200)

	// 1) stale client write that is OLDER than the server's → server wins, client text kept as copy
	res := e.push(item("note", "upsert", id, 1, t0.Add(5*time.Minute), model.Note{Title: "N", Body: "client offline text"}))
	r := res.Results[0]
	if r.Status != "conflict" || r.Version != 2 || r.ConflictCopyID == "" {
		t.Fatalf("server-wins conflict: %+v", r)
	}
	cur := r.Current.(map[string]any)
	if cur["body"] != "server v2" {
		t.Fatalf("current should be server version: %v", cur)
	}
	copyNote := decode[model.Note](t, e.must("GET", "/notes/"+r.ConflictCopyID, nil, 200).Raw)
	if !strings.HasPrefix(copyNote.Title, store.ConflictCopyPrefix) || copyNote.Body != "client offline text" {
		t.Fatalf("conflict copy wrong: %+v", copyNote)
	}

	// 2) stale client write that is NEWER than the server's → client wins, server text kept as copy
	res = e.push(item("note", "upsert", id, 1, t0.Add(20*time.Minute), model.Note{Title: "N", Body: "client newer"}))
	r = res.Results[0]
	if r.Status != "applied" || r.Version != 3 || r.ConflictCopyID == "" {
		t.Fatalf("client-wins conflict: %+v", r)
	}
	copyNote = decode[model.Note](t, e.must("GET", "/notes/"+r.ConflictCopyID, nil, 200).Raw)
	if copyNote.Body != "server v2" {
		t.Fatalf("server text not preserved: %+v", copyNote)
	}
	live := decode[model.Note](t, e.must("GET", "/notes/"+id, nil, 200).Raw)
	if live.Body != "client newer" {
		t.Fatalf("live note wrong: %+v", live)
	}

	// 3) same body, stale version, older → conflict but no copy (nothing to lose)
	res = e.push(item("note", "upsert", id, 1, t0, model.Note{Title: "N", Body: "client newer"}))
	if res.Results[0].Status != "conflict" || res.Results[0].ConflictCopyID != "" {
		t.Fatalf("identical-body conflict should not create a copy: %+v", res.Results[0])
	}

	// 4) stale delete, newer than server → applied, server text preserved as copy
	res = e.push(item("note", "delete", id, 1, t0.Add(time.Hour), nil))
	if res.Results[0].Status != "applied" || res.Results[0].ConflictCopyID == "" {
		t.Fatalf("stale delete: %+v", res.Results[0])
	}
	// 5) events use plain LWW (no copies)
	cal := decode[struct {
		Calendars []model.Calendar `json:"calendars"`
	}](t, e.must("GET", "/calendars", nil, 200).Raw).Calendars[0].ID
	evID := uuid.NewString()
	ev := model.Event{CalendarID: cal, Title: "A", StartAt: t0, EndAt: t0.Add(time.Hour), Timezone: "UTC"}
	e.push(item("event", "upsert", evID, 0, t0, ev))
	ev.Title = "B"
	e.push(item("event", "upsert", evID, 1, t0.Add(time.Minute), ev))
	ev.Title = "C-old"
	res = e.push(item("event", "upsert", evID, 1, t0.Add(30*time.Second), ev))
	if res.Results[0].Status != "conflict" || res.Results[0].Current.(map[string]any)["title"] != "B" {
		t.Fatalf("event LWW: %+v", res.Results[0])
	}
	// 6) idempotent re-push of an already applied item (same base, same data) bumps version harmlessly
	res = e.push(item("event", "delete", evID, 2, t0.Add(time.Hour), nil), item("event", "delete", evID, 3, t0.Add(time.Hour), nil))
	if res.Results[0].Status != "applied" || res.Results[1].Status != "applied" || res.Results[1].Version != 3 {
		t.Fatalf("double delete: %+v", res.Results)
	}
}

func TestSyncPagination(t *testing.T) {
	e := newEnv(t)
	e.register("page@example.com")
	t0 := time.Date(2026, 2, 1, 9, 0, 0, 0, time.UTC)
	var items []store.PushItem
	for i := 0; i < 12; i++ {
		items = append(items, item("note", "upsert", uuid.NewString(), 0, t0, model.Note{Title: "n", Body: formatInt(int64(i))}))
	}
	e.push(items...)
	seen := map[string]bool{}
	since := int64(0)
	pages := 0
	for {
		p := decode[store.PullResponse](t, e.must("GET", "/sync?since="+formatInt(since)+"&limit=5", nil, 200).Raw)
		pages++
		for _, n := range p.Notes {
			if seen[n.ID] {
				t.Fatalf("note %s returned twice", n.ID)
			}
			seen[n.ID] = true
		}
		if p.LastSeq <= since && p.HasMore {
			t.Fatal("pagination does not advance")
		}
		since = p.LastSeq
		if !p.HasMore {
			break
		}
		if pages > 10 {
			t.Fatal("too many pages")
		}
	}
	if len(seen) != 12 || pages != 3 {
		t.Fatalf("saw %d notes in %d pages", len(seen), pages)
	}
}

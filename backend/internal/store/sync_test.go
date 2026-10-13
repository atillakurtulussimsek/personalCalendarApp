package store

import (
	"testing"
	"time"
)

func TestDecide(t *testing.T) {
	t0 := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)
	cases := []struct {
		name         string
		exists       bool
		curVer       int64
		curUpd       time.Time
		it           PushItem
		apply, confl bool
	}{
		{"new upsert", false, 0, time.Time{}, PushItem{Op: OpUpsert}, true, false},
		{"delete unknown", false, 0, time.Time{}, PushItem{Op: OpDelete}, false, false},
		{"fast path", true, 3, t0, PushItem{Op: OpUpsert, BaseVersion: 3, UpdatedAt: t0.Add(-time.Hour)}, true, false},
		{"stale but newer", true, 3, t0, PushItem{Op: OpUpsert, BaseVersion: 2, UpdatedAt: t0.Add(time.Minute)}, true, true},
		{"stale and older", true, 3, t0, PushItem{Op: OpUpsert, BaseVersion: 2, UpdatedAt: t0.Add(-time.Minute)}, false, true},
		{"stale same time", true, 3, t0, PushItem{Op: OpDelete, BaseVersion: 1, UpdatedAt: t0}, false, true},
	}
	for _, c := range cases {
		a, k := decide(c.exists, c.curVer, c.curUpd, c.it)
		if a != c.apply || k != c.confl {
			t.Errorf("%s: got apply=%v conflict=%v want %v %v", c.name, a, k, c.apply, c.confl)
		}
	}
}

func TestBooleanQuery(t *testing.T) {
	if got := booleanQuery(`veli +toplantı "x"`); got != "+veli* +toplantı* +x*" {
		t.Fatalf("got %q", got)
	}
}

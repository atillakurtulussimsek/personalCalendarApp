package notify

import (
	"context"
	"sync"
	"testing"
	"time"
)

type fakePusher struct {
	mu    sync.Mutex
	calls []string
}

func (f *fakePusher) Push(_ context.Context, userID, from string, seq int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, userID+"/"+from)
}

func TestHubFanOutSkipsOriginAndDebouncesPush(t *testing.T) {
	fp := &fakePusher{}
	h := NewHub(fp, 30*time.Millisecond)
	a, leaveA := h.Subscribe("u1", "devA")
	b, leaveB := h.Subscribe("u1", "devB")
	other, leaveO := h.Subscribe("u2", "devX")
	defer leaveA()
	defer leaveB()
	defer leaveO()

	for i := 0; i < 5; i++ {
		h.Changed("u1", "devA", int64(i+1))
	}
	select {
	case s := <-b:
		if s.Type != "sync" || s.Seq != 1 || s.FromDevID != "devA" {
			t.Fatalf("bad signal %+v", s)
		}
	case <-time.After(time.Second):
		t.Fatal("devB got no signal")
	}
	select {
	case <-a:
		t.Fatal("origin device must not be notified")
	case <-other:
		t.Fatal("other user must not be notified")
	case <-time.After(50 * time.Millisecond):
	}
	time.Sleep(80 * time.Millisecond)
	fp.mu.Lock()
	defer fp.mu.Unlock()
	if len(fp.calls) != 1 || fp.calls[0] != "u1/devA" {
		t.Fatalf("push should be debounced to one call, got %v", fp.calls)
	}
	leaveB()
	if h.LiveCount("u1") != 1 {
		t.Fatal("unsubscribe failed")
	}
}

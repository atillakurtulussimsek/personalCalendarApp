// Package notify fans out "something changed, sync now" signals to a user's
// other devices: over WebSocket for connected clients and over FCM data
// messages for Android devices with a push token.
package notify

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

// Signal is what clients receive.
type Signal struct {
	Type      string `json:"type"` // "sync"
	Seq       int64  `json:"seq"`
	FromDevID string `json:"from_device_id,omitempty"`
}

// Pusher sends a signal to the offline (push) channel of a user.
type Pusher interface {
	Push(ctx context.Context, userID, fromDeviceID string, seq int64)
}

type subscriber struct {
	deviceID string
	ch       chan Signal
}

// Hub tracks live WebSocket subscribers per user and debounces notifications.
type Hub struct {
	mu       sync.Mutex
	subs     map[string]map[*subscriber]struct{}
	pending  map[string]*time.Timer
	pusher   Pusher
	debounce time.Duration
}

// NewHub creates a hub; pusher may be nil.
func NewHub(pusher Pusher, debounce time.Duration) *Hub {
	return &Hub{subs: map[string]map[*subscriber]struct{}{}, pending: map[string]*time.Timer{}, pusher: pusher, debounce: debounce}
}

// Subscribe registers a live connection for userID; call the returned func to leave.
func (h *Hub) Subscribe(userID, deviceID string) (<-chan Signal, func()) {
	s := &subscriber{deviceID: deviceID, ch: make(chan Signal, 8)}
	h.mu.Lock()
	if h.subs[userID] == nil {
		h.subs[userID] = map[*subscriber]struct{}{}
	}
	h.subs[userID][s] = struct{}{}
	h.mu.Unlock()
	return s.ch, func() {
		h.mu.Lock()
		delete(h.subs[userID], s)
		if len(h.subs[userID]) == 0 {
			delete(h.subs, userID)
		}
		h.mu.Unlock()
	}
}

// Changed is called by the store after every committed write.
// Live subscribers (other than the originating device) are told immediately;
// the push channel is debounced so a burst of writes becomes one push.
func (h *Hub) Changed(userID, fromDeviceID string, seq int64) {
	sig := Signal{Type: "sync", Seq: seq, FromDevID: fromDeviceID}
	h.mu.Lock()
	for s := range h.subs[userID] {
		if s.deviceID != "" && s.deviceID == fromDeviceID {
			continue
		}
		select {
		case s.ch <- sig:
		default: // slow client: it will catch up on its next sync anyway
		}
	}
	if h.pusher != nil {
		if t, ok := h.pending[userID]; ok {
			t.Stop()
		}
		h.pending[userID] = time.AfterFunc(h.debounce, func() {
			h.mu.Lock()
			delete(h.pending, userID)
			h.mu.Unlock()
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			h.pusher.Push(ctx, userID, fromDeviceID, seq)
		})
	}
	h.mu.Unlock()
}

// LiveCount returns the number of live subscribers of a user (tests, metrics).
func (h *Hub) LiveCount(userID string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.subs[userID])
}

var _ = slog.Info

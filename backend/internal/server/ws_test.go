package server_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/google/uuid"
)

// Device B keeps a WebSocket open; device A writes via REST and via /sync.
// B must receive "sync" signals, A (the origin) must not.
func TestWebSocketSignals(t *testing.T) {
	e := newEnv(t)
	e.register("ws@example.com") // device A token in e.token
	tokenA := e.token
	// log in as device B
	devB := uuid.NewString()
	l := e.must("POST", "/auth/login", map[string]any{"email": "ws@example.com", "password": "password123", "device_id": devB, "device_platform": "macos"}, 200)
	tokenB := l.Body["access_token"].(string)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	wsURL := strings.Replace(e.srv.URL, "http://", "ws://", 1) + "/ws?token=" + tokenB
	connB, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = connB.CloseNow() }()
	var hello map[string]any
	if err := wsjson.Read(ctx, connB, &hello); err != nil || hello["type"] != "hello" {
		t.Fatalf("expected hello, got %v err=%v", hello, err)
	}
	wsA, _, err := websocket.Dial(ctx, strings.Replace(e.srv.URL, "http://", "ws://", 1)+"/ws?token="+tokenA, nil)
	if err != nil {
		t.Fatalf("dial A: %v", err)
	}
	defer func() { _ = wsA.CloseNow() }()
	_ = wsjson.Read(ctx, wsA, &hello)

	// unauthenticated dial is refused
	if _, res, err := websocket.Dial(ctx, strings.Replace(e.srv.URL, "http://", "ws://", 1)+"/ws", nil); err == nil || res == nil || res.StatusCode != 401 {
		t.Fatalf("expected 401 without token, got err=%v res=%v", err, res)
	}

	// A writes through REST
	e.token = tokenA
	e.must("POST", "/notes", map[string]any{"title": "from A", "body": "x"}, 201)
	var sig map[string]any
	rctx, rcancel := context.WithTimeout(ctx, 3*time.Second)
	defer rcancel()
	if err := wsjson.Read(rctx, connB, &sig); err != nil {
		t.Fatalf("B got no signal: %v", err)
	}
	if sig["type"] != "sync" || sig["seq"].(float64) < 1 {
		t.Fatalf("bad signal %v", sig)
	}
	// A writes through /sync
	e.must("POST", "/sync", map[string]any{"items": []map[string]any{{
		"entity": "note", "op": "upsert", "id": uuid.NewString(), "base_version": 0,
		"updated_at": time.Now().UTC().Format(time.RFC3339), "data": map[string]any{"title": "n", "body": "b"},
	}}}, 200)
	rctx2, rcancel2 := context.WithTimeout(ctx, 3*time.Second)
	defer rcancel2()
	if err := wsjson.Read(rctx2, connB, &sig); err != nil {
		t.Fatalf("B got no signal after push: %v", err)
	}
	// origin device A must stay silent
	actx, acancel := context.WithTimeout(ctx, 300*time.Millisecond)
	defer acancel()
	if err := wsjson.Read(actx, wsA, &sig); err == nil {
		t.Fatalf("origin device received its own signal: %v", sig)
	}
}

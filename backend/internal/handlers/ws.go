package handlers

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/atillasimsek/personal-calendar/backend/internal/httpx"
)

// websocket handles GET /ws?token=<access token>.
// The server sends {"type":"sync","seq":N} whenever another device of the
// user changes data; the client answers by running a sync. The server also
// sends {"type":"hello","seq":N} on connect so a client that missed signals
// while disconnected can compare with its last_seq.
func (h *Handlers) websocket(w http.ResponseWriter, r *http.Request) {
	if h.Hub == nil {
		httpx.WriteError(w, httpx.NotFound("live sync disabled"))
		return
	}
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{OriginPatterns: []string{"*"}})
	if err != nil {
		return
	}
	defer func() { _ = c.CloseNow() }()
	userID := httpx.UserID(r.Context())
	deviceID := httpx.DeviceID(r.Context())
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	seq, _ := h.Store.LastSeq(ctx)
	if err := wsjson.Write(ctx, c, map[string]any{"type": "hello", "seq": seq}); err != nil {
		return
	}
	signals, leave := h.Hub.Subscribe(userID, deviceID)
	defer leave()

	// Reader: drains client frames (pings/pongs/close) so the connection stays healthy.
	go func() {
		defer cancel()
		for {
			if _, _, err := c.Read(ctx); err != nil {
				return
			}
		}
	}()

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case s := <-signals:
			if err := wsjson.Write(ctx, c, s); err != nil {
				return
			}
		case <-ticker.C:
			pctx, pcancel := context.WithTimeout(ctx, 10*time.Second)
			err := c.Ping(pctx)
			pcancel()
			if err != nil {
				slog.Debug("ws ping failed", "user", userID, "err", err)
				return
			}
		}
	}
}

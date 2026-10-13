package notify

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"github.com/atillasimsek/personal-calendar/backend/internal/db"
)

// FCM sends silent data messages through the Firebase Cloud Messaging HTTP v1 API.
// It is configured with a service-account JSON (FCM_SERVICE_ACCOUNT_JSON).
type FCM struct {
	projectID string
	client    *http.Client
	q         *db.Queries
	sqlDB     *sql.DB
	endpoint  string
}

// NewFCM builds a sender from service-account JSON; returns nil, nil when creds are empty.
func NewFCM(ctx context.Context, serviceAccountJSON []byte, sqlDB *sql.DB) (*FCM, error) {
	if len(serviceAccountJSON) == 0 {
		return nil, nil
	}
	creds, err := google.CredentialsFromJSONWithType(ctx, serviceAccountJSON, google.ServiceAccount, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("fcm credentials: %w", err)
	}
	var meta struct {
		ProjectID string `json:"project_id"`
	}
	_ = json.Unmarshal(serviceAccountJSON, &meta)
	if meta.ProjectID == "" {
		return nil, fmt.Errorf("fcm credentials: project_id missing")
	}
	client := oauth2.NewClient(ctx, creds.TokenSource)
	client.Timeout = 10 * time.Second
	return &FCM{
		projectID: meta.ProjectID,
		client:    client,
		q:         db.New(sqlDB),
		sqlDB:     sqlDB,
		endpoint:  "https://fcm.googleapis.com/v1/projects/" + meta.ProjectID + "/messages:send",
	}, nil
}

// Push sends a data-only "sync" message to every device of the user that has a
// token, except the one that caused the change. Invalid tokens are cleared.
func (f *FCM) Push(ctx context.Context, userID, fromDeviceID string, seq int64) {
	devices, err := f.q.ListDevices(ctx, userID)
	if err != nil {
		slog.Warn("fcm list devices", "err", err)
		return
	}
	for _, d := range devices {
		if !d.PushToken.Valid || d.PushToken.String == "" || d.ID == fromDeviceID {
			continue
		}
		if err := f.send(ctx, d.PushToken.String, seq); err != nil {
			slog.Warn("fcm send", "device", d.ID, "err", err)
			if isUnregistered(err) {
				_ = f.q.UpdateDevicePushToken(ctx, db.UpdateDevicePushTokenParams{PushToken: sql.NullString{}, UpdatedAt: time.Now().UTC(), ID: d.ID, UserID: userID})
			}
		}
	}
}

type fcmError struct {
	status int
	body   string
}

func (e *fcmError) Error() string { return fmt.Sprintf("fcm %d: %s", e.status, e.body) }

func isUnregistered(err error) bool {
	e, ok := err.(*fcmError)
	return ok && (e.status == http.StatusNotFound || bytes.Contains([]byte(e.body), []byte("UNREGISTERED")))
}

func (f *FCM) send(ctx context.Context, token string, seq int64) error {
	payload := map[string]any{
		"message": map[string]any{
			"token": token,
			"data":  map[string]string{"type": "sync", "seq": strconv.FormatInt(seq, 10)},
			"android": map[string]any{
				"priority": "high", // wake the app even in Doze (within the OS quota)
				"ttl":      "3600s",
			},
		},
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, f.endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
		return &fcmError{status: res.StatusCode, body: string(b)}
	}
	return nil
}

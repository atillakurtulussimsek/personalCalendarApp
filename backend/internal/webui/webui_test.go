package webui

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"testing/fstest"
)

func TestHandler(t *testing.T) {
	root := fstest.MapFS{
		"index.html":   {Data: []byte("<html>app</html>")},
		"main.dart.js": {Data: []byte("js")},
		"sqlite3.wasm": {Data: []byte("\x00asm")},
	}
	api := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTeapot) })
	h := Handler(root, api)

	cases := []struct {
		method, path, accept string
		want                 int
	}{
		{"GET", "/", "text/html", 200},
		{"GET", "/main.dart.js", "*/*", 200},
		{"GET", "/sqlite3.wasm", "*/*", 200},
		{"GET", "/some/route", "text/html", 200},       // SPA fallback
		{"GET", "/calendars", "application/json", 418}, // API
		{"POST", "/", "text/html", 418},                // non-GET to API
		{"GET", "/missing.js", "text/html", 418},       // asset-looking path → API 404
	}
	for _, c := range cases {
		req := httptest.NewRequest(c.method, c.path, nil)
		req.Header.Set("Accept", c.accept)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Errorf("%s %s: got %d want %d", c.method, c.path, rec.Code, c.want)
		}
	}
	req := httptest.NewRequest("GET", "/sqlite3.wasm", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if ct := rec.Header().Get("Content-Type"); ct != "application/wasm" {
		t.Errorf("wasm content type %q", ct)
	}
	// revalidation: same ETag → 304, and never a long max-age
	req = httptest.NewRequest("GET", "/main.dart.js", nil)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	etag := rec.Header().Get("ETag")
	if etag == "" || rec.Header().Get("Cache-Control") != "no-cache" {
		t.Fatalf("missing etag/no-cache: %v", rec.Header())
	}
	req = httptest.NewRequest("GET", "/main.dart.js", nil)
	req.Header.Set("If-None-Match", etag)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotModified {
		t.Errorf("want 304 on matching ETag, got %d", rec.Code)
	}
	if !Available(root) || Available(fstest.MapFS{}) {
		t.Error("Available")
	}
}

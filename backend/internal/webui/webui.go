// Package webui serves the Flutter web build embedded into the binary.
//
// `make build` (or the root Dockerfile) copies app/build/web into dist/ before
// `go build`; without it only dist/.keep is embedded and the API runs headless.
package webui

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"io/fs"
	"net/http"
	"path"
	"strings"
	"sync"
)

//go:embed all:dist
var embedded embed.FS

// Dist is the embedded web root.
func Dist() fs.FS {
	sub, err := fs.Sub(embedded, "dist")
	if err != nil {
		panic(err)
	}
	return sub
}

// Available reports whether a web build was embedded.
func Available(root fs.FS) bool {
	_, err := fs.Stat(root, "index.html")
	return err == nil
}

// Handler serves static files from root. Unknown paths that look like page
// navigations fall back to index.html; everything else is passed to next
// (the API's JSON 404).
//
// Flutter web asset names are not content-hashed (main.dart.js, fonts,
// FontManifest.json…), so long cache lifetimes would mix files from different
// deploys (e.g. a stale tree-shaken icon font). Every response is therefore
// "no-cache" with a strong ETag: browsers revalidate and get a cheap 304 when
// nothing changed.
func Handler(root fs.FS, next http.Handler) http.Handler {
	files := http.FileServer(http.FS(root))
	etags := &etagCache{root: root, m: map[string]string{}}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			next.ServeHTTP(w, r)
			return
		}
		p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if p == "" {
			p = "index.html"
		}
		if info, err := fs.Stat(root, p); err == nil && !info.IsDir() {
			setHeaders(w, p, etags.get(p))
			files.ServeHTTP(w, r)
			return
		}
		if strings.Contains(r.Header.Get("Accept"), "text/html") && path.Ext(p) == "" {
			setHeaders(w, "index.html", etags.get("index.html"))
			r2 := r.Clone(r.Context())
			r2.URL.Path = "/"
			files.ServeHTTP(w, r2)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func setHeaders(w http.ResponseWriter, p, etag string) {
	w.Header().Set("Cache-Control", "no-cache")
	if etag != "" {
		// net/http's FileServer honours If-None-Match against this header (304)
		w.Header().Set("ETag", etag)
	}
	if strings.HasSuffix(p, ".wasm") {
		w.Header().Set("Content-Type", "application/wasm")
	}
}

// etagCache hashes embedded files once (they never change at runtime).
type etagCache struct {
	root fs.FS
	mu   sync.Mutex
	m    map[string]string
}

func (c *etagCache) get(p string) string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, ok := c.m[p]; ok {
		return e
	}
	b, err := fs.ReadFile(c.root, p)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(b)
	e := `"` + hex.EncodeToString(sum[:12]) + `"`
	c.m[p] = e
	return e
}

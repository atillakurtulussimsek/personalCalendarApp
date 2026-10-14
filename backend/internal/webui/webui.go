// Package webui serves the Flutter web build embedded into the binary.
//
// `make build` (or the root Dockerfile) copies app/build/web into dist/ before
// `go build`; without it only dist/.keep is embedded and the API runs headless.
package webui

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
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
func Handler(root fs.FS, next http.Handler) http.Handler {
	files := http.FileServer(http.FS(root))
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
			setCacheHeaders(w, p)
			files.ServeHTTP(w, r)
			return
		}
		if strings.Contains(r.Header.Get("Accept"), "text/html") && path.Ext(p) == "" {
			setCacheHeaders(w, "index.html")
			r2 := r.Clone(r.Context())
			r2.URL.Path = "/"
			files.ServeHTTP(w, r2)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Entry points and the service worker must always be revalidated so a deploy
// is picked up immediately; hashed/static assets can be cached.
func setCacheHeaders(w http.ResponseWriter, p string) {
	switch p {
	case "index.html", "flutter_bootstrap.js", "flutter_service_worker.js", "version.json", "manifest.json", "main.dart.js",
		"drift_worker.js", "sqlite3.wasm":
		w.Header().Set("Cache-Control", "no-cache")
	default:
		w.Header().Set("Cache-Control", "public, max-age=86400")
	}
	if strings.HasSuffix(p, ".wasm") {
		w.Header().Set("Content-Type", "application/wasm")
	}
}

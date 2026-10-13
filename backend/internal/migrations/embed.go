// Package migrations embeds the SQL migration files so the binary can apply them at startup.
package migrations

import "embed"

// FS contains the *.up.sql / *.down.sql files.
//
//go:embed *.sql
var FS embed.FS

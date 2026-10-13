# Backend — Personal Calendar API

Go 1.23+ · chi · MySQL 8 · sqlc · golang-migrate · slog

## Run locally

```bash
cp .env.example .env            # fill DATABASE_URL and JWT_SECRET
make run                        # migrations are applied automatically at startup
curl localhost:8080/healthz
```

Required tools for development (not for running the binary):

```bash
go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
go install -tags mysql github.com/golang-migrate/migrate/v4/cmd/migrate@latest
go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
```

## Tests

```bash
make test-unit                                   # no database needed
TEST_DATABASE_URL='root:@tcp(127.0.0.1:3306)/personal_calendar_test' make test
```

Integration tests (`internal/server/*_test.go`) run the full router against a real
MySQL and **drop every table** in `TEST_DATABASE_URL` before each test. Use a
throwaway database.

## Layout

```
cmd/api              main: config, DB, migrations, HTTP server, graceful shutdown
internal/config      env parsing
internal/migrations  embedded SQL migrations (golang-migrate)
internal/db          sqlc-generated queries (do not edit) + queries/*.sql sources
internal/model       JSON DTOs and row conversions
internal/store       the single write path: versions, server_seq, conflict policy, sync push/pull
internal/rrule       RRULE expansion with exceptions (teambition/rrule-go)
internal/auth        argon2id, JWT access tokens, refresh tokens
internal/handlers    HTTP handlers per resource
internal/server      router, middleware, DB open/migrate
internal/httpx       JSON + error envelope helpers
```

## Deploy to Dokploy

1. Create a **Compose** service pointing at this repository, compose path `backend/docker-compose.yml`.
2. Set environment variables: `JWT_SECRET`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`
   (optionally `ALLOW_REGISTRATION=false` after your account exists, `CORS_ORIGINS`, `API_PORT`).
3. Add a domain to the `api` service on port 8080; Dokploy's Traefik terminates HTTPS
   (`TRUSTED_PROXIES=1` is the compose default so rate limiting sees real client IPs).
4. Deploy. The API applies migrations on boot. The MySQL data lives in the `mysql-data` volume.

To use an external MySQL instead, set `DATABASE_URL` and remove the `db` service.

## API

See [`../docs/api.yaml`](../docs/api.yaml) (OpenAPI 3) and
[`../docs/architecture.md`](../docs/architecture.md) for the sync protocol.

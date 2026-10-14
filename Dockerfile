# One image = API + embedded web UI.
#   docker build -t personal-calendar .
# Stage 1 builds the Flutter web app, stage 2 embeds it into the Go binary,
# stage 3 is a minimal runtime.

# ---- web ---------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:3.47.7 AS web
WORKDIR /src/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
RUN ./tool/fetch_web_assets.sh \
 && flutter build web --release --no-web-resources-cdn

# ---- api ---------------------------------------------------------------
FROM golang:1.26-alpine AS api
WORKDIR /src/backend
RUN apk add --no-cache ca-certificates tzdata
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
COPY --from=web /src/app/build/web/ ./internal/webui/dist/
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# ---- runtime -----------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=api /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=api /out/api /api
ENV ADDR=:8080 TZ=UTC
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/api"]

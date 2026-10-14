# One image = API + embedded web UI.
#   docker build -t personal-calendar .
# Stage 1 builds the Flutter web app, stage 2 embeds it into the Go binary,
# stage 3 is a minimal runtime.

# ---- web ---------------------------------------------------------------
# Flutter is installed from the official repository at a pinned tag (no third-party image).
FROM debian:bookworm-slim AS web
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}" \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/opt/pub-cache
RUN git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --enable-web >/dev/null \
 && flutter precache --web
WORKDIR /src/app
COPY app/ ./
RUN flutter pub get \
 && ./tool/fetch_web_assets.sh \
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

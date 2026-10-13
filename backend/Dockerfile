# ---- build stage -----------------------------------------------------------
FROM golang:1.26-alpine AS build
WORKDIR /src
RUN apk add --no-cache ca-certificates tzdata
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# ---- runtime stage ---------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /out/api /api
ENV ADDR=:8080 TZ=UTC
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/api"]

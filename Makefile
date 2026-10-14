# One-shot build: Flutter web app embedded into the Go API binary.
#   make build        → backend/bin/api (serves API + web UI on one port)
#   make docker       → same, as a container image (see Dockerfile)
#   make apk / macos  → native clients

APP     := app
BACKEND := backend
WEBDIST := $(BACKEND)/internal/webui/dist

.PHONY: build web embed api apk macos test docker clean run

build: web embed api

web:
	cd $(APP) && flutter pub get && ./tool/fetch_web_assets.sh && flutter build web --release --no-web-resources-cdn

embed:
	find $(WEBDIST) -mindepth 1 ! -name .keep -exec rm -rf {} +
	cp -R $(APP)/build/web/. $(WEBDIST)/

api:
	cd $(BACKEND) && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/api ./cmd/api

run: build
	cd $(BACKEND) && ./bin/api

apk:
	cd $(APP) && flutter build apk --release

macos:
	cd $(APP) && flutter build macos --release

test:
	cd $(BACKEND) && go test ./... -count=1
	cd $(APP) && flutter test

docker:
	docker build -t personal-calendar .

clean:
	find $(WEBDIST) -mindepth 1 ! -name .keep -exec rm -rf {} +
	rm -rf $(BACKEND)/bin $(APP)/build/web

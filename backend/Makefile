GOBIN ?= $(shell go env GOPATH)/bin

.PHONY: run build test test-unit lint generate migrate-new tidy docker

run:            ## start the API (reads .env)
	go run ./cmd/api

build:          ## build static binary into bin/
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/api ./cmd/api

test:           ## all tests; integration tests need TEST_DATABASE_URL
	go test ./... -count=1

test-unit:      ## tests that do not need a database
	go test ./internal/auth/ ./internal/rrule/ ./internal/store/ -count=1

lint:
	go vet ./...
	$(GOBIN)/golangci-lint run ./...

generate:       ## regenerate sqlc code after editing internal/db/queries or migrations
	$(GOBIN)/sqlc generate

migrate-new:    ## make migrate-new name=add_tasks
	$(GOBIN)/migrate create -ext sql -dir internal/migrations -seq $(name)

tidy:
	go mod tidy

docker:
	docker compose up --build

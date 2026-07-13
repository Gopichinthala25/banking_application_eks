# Banking Platform — developer Makefile
#
# Go runs inside a Docker container by default so a host Go install is NOT
# required (the project baseline is Go 1.25). To use a locally installed Go
# instead, run:  make <target> USE_LOCAL_GO=1

SHELL := /bin/bash

GO_IMAGE   ?= golang:1.25-alpine
CACHE_DIR  ?= $(HOME)/.cache/banking-platform
MODULES    := pkg templates/service-template

ifeq ($(USE_LOCAL_GO),1)
  GO := go
  define run_in
	cd $(1) && $(GO) $(2)
  endef
else
  GO := docker run --rm \
	-v $(CURDIR):/src \
	-v $(CACHE_DIR)/gocache:/root/.cache/go-build \
	-v $(CACHE_DIR)/gomodcache:/go/pkg/mod \
	-e GOFLAGS=-buildvcs=false \
	$(GO_IMAGE)
  define run_in
	$(GO) sh -c "cd /src/$(1) && go $(2)"
  endef
endif

.DEFAULT_GOAL := help

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'

## tidy: go mod tidy for every module
.PHONY: tidy
tidy:
	@mkdir -p $(CACHE_DIR)/gocache $(CACHE_DIR)/gomodcache
	@$(foreach m,$(MODULES),echo ">> tidy $(m)"; GOWORK=off $(call run_in,$(m),mod tidy) &&) true

## build: compile every module
.PHONY: build
build:
	@mkdir -p $(CACHE_DIR)/gocache $(CACHE_DIR)/gomodcache
	@$(foreach m,$(MODULES),echo ">> build $(m)"; GOWORK=off $(call run_in,$(m),build ./...) &&) true

## test: run unit tests for every module
.PHONY: test
test:
	@mkdir -p $(CACHE_DIR)/gocache $(CACHE_DIR)/gomodcache
	@$(foreach m,$(MODULES),echo ">> test $(m)"; GOWORK=off $(call run_in,$(m),test ./...) &&) true

## run-template: run the service template locally (in-memory, no deps)
.PHONY: run-template
run-template:
	cd templates/service-template && \
	POSTGRES_ENABLED=false OTEL_ENABLED=false LOG_FORMAT=console go run ./cmd

## docker-build-template: build the service-template image (context = repo root)
.PHONY: docker-build-template
docker-build-template:
	docker build -f templates/service-template/Dockerfile -t banking/service-template:dev .

## compose-up: start local Postgres, Redis, Kafka
.PHONY: compose-up
compose-up:
	docker compose up -d

## compose-down: stop local dependencies
.PHONY: compose-down
compose-down:
	docker compose down

## compose-logs: tail local dependency logs
.PHONY: compose-logs
compose-logs:
	docker compose logs -f

## clean: remove build artifacts
.PHONY: clean
clean:
	rm -rf bin dist

.PHONY: build release dev clean test fmt lint deps dialyzer sobelow precommit help docker docker-compose

# Default target
all: build

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")

# Compile the application
build:
	mix compile --warnings-as-errors

# Build escript binary (for native CLI usage)
escript: deps
	mix escript.build

# Build release (for Docker / production)
release: deps
	MIX_ENV=prod mix release familiar --overwrite

# Development server
dev:
	mix phx.server

# Run tests
test:
	mix test

# Run tests with coverage
test-cover:
	mix test --cover

# Stress-test a specific file 50x (usage: make stress FILE=test/familiar/cli/main_test.exs)
stress:
	@for i in $$(seq 1 50); do \
		mix test $(FILE) --no-color 2>&1 | grep -E "tests|failure" | tail -1; \
	done | sort | uniq -c

# Format code
fmt:
	mix format

# Check formatting without modifying
fmt-check:
	mix format --check-formatted

# Lint code
lint:
	mix credo --strict

# Type checking
dialyzer:
	mix dialyzer

# Security scanning
sobelow:
	mix sobelow --config

# Install dependencies
deps:
	mix deps.get

# Setup project from scratch
setup: deps
	mix ecto.create
	mix ecto.migrate

# Run all pre-commit checks (mirrors the pre-commit hook)
precommit:
	mix precommit

# Build Docker image
docker:
	docker build -t familiar .

# Quick start with Docker Compose
docker-compose:
	docker compose run --rm familiar fam init

# Clean build artifacts
clean:
	rm -rf _build/
	rm -f fam

# Deep clean (build + deps + generated)
distclean: clean
	rm -rf deps/
	rm -rf cover/
	rm -rf doc/

# Show current configuration
config:
	mix run -e "IO.inspect(Application.get_all_env(:familiar), pretty: true, limit: :infinity)"

# Help target
help:
	@echo "Available targets:"
	@echo "  build          - Compile the application (warnings as errors)"
	@echo "  escript        - Build escript binary for native CLI"
	@echo "  release        - Build mix release for Docker/production"
	@echo "  dev            - Run development server"
	@echo "  test           - Run test suite"
	@echo "  test-cover     - Run tests with coverage report"
	@echo "  stress         - Stress-test a file 50x (FILE=path/to/test.exs)"
	@echo "  fmt            - Format code"
	@echo "  fmt-check      - Check formatting without modifying"
	@echo "  lint           - Run credo strict"
	@echo "  dialyzer       - Run type checker"
	@echo "  sobelow        - Run security scanner"
	@echo "  precommit      - Run all pre-commit checks"
	@echo "  deps           - Install dependencies"
	@echo "  setup          - Full project setup (deps + db)"
	@echo "  docker         - Build Docker image"
	@echo "  docker-compose - Quick start with Docker Compose"
	@echo "  clean          - Remove build artifacts"
	@echo "  distclean      - Remove build artifacts + deps"
	@echo "  help           - Show this help"

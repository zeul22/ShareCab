# ShareCab development Makefile.
# Run `make` (no args) to see the available targets.
#
# Quick start from a fresh clone:
#   make setup       # install deps, pull docker images
#   make dev         # start mongo + backend (foreground)
#   make seed        # in another terminal: create demo accounts
#
# Daily workflow:
#   make dev         # mongo is idempotent, backend file-watches
#
# Reset everything:
#   make db-reset && make seed

SHELL       := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

API_URL     ?= http://localhost:4000

.DEFAULT_GOAL := help
.PHONY: help setup doctor \
        db-up db-down db-reset db-logs \
        backend backend-test backend-e2e \
        seed \
        app-deps app-android app-ios app-analyze \
        dev stop clean

# -----------------------------------------------------------------------------
# Help — print every target with its `## description` annotation.
# -----------------------------------------------------------------------------
help: ## Show this help
	@awk 'BEGIN { FS = ":.*## "; \
	              printf "ShareCab Makefile\n\nTargets:\n" } \
	      /^[a-zA-Z][a-zA-Z0-9_-]*:.*## / { \
	          printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' \
	    $(MAKEFILE_LIST)
	@echo
	@echo "First-time setup:  make setup && make dev (and \`make seed\` in another shell)"

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
doctor: ## Verify Docker, Node, npm, Flutter are installed
	@for cmd in docker node npm flutter; do \
	  if ! command -v $$cmd >/dev/null; then \
	    echo "✗ $$cmd not found in PATH"; exit 1; \
	  fi; \
	  printf "✓ %-7s %s\n" $$cmd "$$($$cmd --version 2>/dev/null | head -1)"; \
	done
	@docker compose version >/dev/null 2>&1 || \
	  { echo "✗ docker compose not available"; exit 1; }
	@echo "✓ docker compose"

setup: doctor ## First-time: install deps + pull docker images
	@echo "→ installing backend deps"
	@cd backend && npm install
	@echo "→ installing app (Flutter) deps"
	@cd app && flutter pub get
	@echo "→ pulling docker images"
	@docker compose pull mongo
	@echo
	@echo "✓ setup complete. Next: \`make dev\` (then \`make seed\` once)."

# -----------------------------------------------------------------------------
# Database (Docker Mongo)
# -----------------------------------------------------------------------------
db-up: ## Start MongoDB via docker compose (idempotent)
	@docker compose up -d mongo
	@printf "→ waiting for mongo to be healthy"
	@for i in {1..30}; do \
	  if [ "$$(docker inspect --format='{{.State.Health.Status}}' sharecab-mongo 2>/dev/null)" = "healthy" ]; then \
	    echo " ready"; exit 0; \
	  fi; \
	  printf "."; sleep 1; \
	done; \
	echo; echo "✗ mongo did not become healthy in 30s"; exit 1

db-down: ## Stop MongoDB (data preserved in named volume)
	@docker compose down

db-reset: ## DESTRUCTIVE — wipe Mongo data volume and restart fresh
	@docker compose down -v
	@$(MAKE) -s db-up
	@echo "✓ mongo wiped + restarted. Run \`make seed\` to recreate demo accounts."

db-logs: ## Tail MongoDB logs
	@docker compose logs -f mongo

# -----------------------------------------------------------------------------
# Backend
# -----------------------------------------------------------------------------
backend: db-up ## Start backend (nodemon, watches files, against docker mongo)
	@cd backend && npm run dev

backend-test: ## Run the backend Jest suite
	@cd backend && npm test

backend-e2e: ## Start backend against in-memory mongo (no docker required)
	@cd backend && npm run dev:e2e

# -----------------------------------------------------------------------------
# Seeding
# -----------------------------------------------------------------------------
seed: ## Seed the 3 demo accounts (R1, R2, Driver) — needs backend running
	@API_URL=$(API_URL) bash backend/scripts/seed-demo.sh

# -----------------------------------------------------------------------------
# App (Flutter)
# -----------------------------------------------------------------------------
app-deps: ## flutter pub get (refresh app deps)
	@cd app && flutter pub get

app-android: ## Run app on the Android emulator (must be booted)
	@cd app && flutter run -d emulator-5554

android-emu: ## Boot the Pixel_9_Pro AVD with Google DNS (fixes places.googleapis lookup failures)
	@echo "→ killing any running emulator-5554 (if present)"
	@-adb -s emulator-5554 emu kill >/dev/null 2>&1 || true
	@for i in {1..10}; do \
	  adb devices | grep -q "emulator-5554" || break; sleep 1; \
	done
	@echo "→ launching Pixel_9_Pro with -dns-server 8.8.8.8,8.8.4.4"
	@AVD=$${ANDROID_AVD:-Pixel_9_Pro}; \
	  EMU=$$(dirname "$$(dirname "$$(which adb)")")/emulator/emulator; \
	  nohup "$$EMU" -avd "$$AVD" -dns-server 8.8.8.8,8.8.4.4 -no-snapshot-load -netfast \
	    >/tmp/emulator-$$AVD.log 2>&1 &
	@echo "→ waiting for boot (this takes ~30-60s on a cold boot)"
	@adb wait-for-device
	@until [ "$$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
	@echo "✓ emulator ready. Run \`make app-android\` next."

app-ios: ## Run app on the iOS simulator (must be booted)
	@cd app && flutter run -d ios

app-analyze: ## Static analysis on the Flutter app
	@cd app && flutter analyze

# -----------------------------------------------------------------------------
# Composite targets
# -----------------------------------------------------------------------------
dev: db-up ## Start mongo + backend in foreground (Ctrl-C to stop backend)
	@echo "→ starting backend (nodemon). Run \`make seed\` in another shell once."
	@cd backend && npm run dev

stop: ## Stop docker services (foreground backend must be Ctrl-C'd separately)
	@docker compose down
	@echo "✓ docker services stopped."

clean: ## DESTRUCTIVE — nuke data volumes, node_modules, flutter build artifacts
	@docker compose down -v
	@rm -rf backend/node_modules backend/.mongo-data
	@cd app && flutter clean
	@echo "✓ clean. Run \`make setup\` to bootstrap again."

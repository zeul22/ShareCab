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
        r1 r2 d1 run-sim \
        loc loc-r1 loc-r2 loc-d1 loc-clear set-sim-location \
        dev stop clean

# -----------------------------------------------------------------------------
# Named iPhone 16e simulators used for multi-device flow testing.
# Lifted to top-level so both the `run-sim` and `loc*` recipes share them.
# -----------------------------------------------------------------------------
RIDER_A_SIM := iPhone 16e (Rider A)
RIDER_B_SIM := iPhone 16e (Rider B)
DRIVER_SIM  := iPhone 16e (Driver)

# Default coords for `make loc`. Picked Indiranagar, Bangalore — central
# enough that matched riders + a nearby driver all fall inside the 2-4 km
# pickup/drop bands the matching engine uses. Override per-invocation:
#   make loc LAT=12.9352 LNG=77.6245   # Koramangala
LAT ?= 12.9784
LNG ?= 77.6408

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
# Multi-device flow testing (iPhone 16e × 3)
# -----------------------------------------------------------------------------
# Three named simulators, two riders + one driver, for verifying the
# matching + dispatch flow end-to-end. Each target auto-boots its
# simulator (and opens Simulator.app) if not booted, then `flutter run`
# against its UDID.
#
# One-time creation on a fresh machine (runtime id from `simctl list runtimes`):
#   xcrun simctl create "iPhone 16e (Rider A)" "iPhone 16e" com.apple.CoreSimulator.SimRuntime.iOS-26-3
#   xcrun simctl create "iPhone 16e (Rider B)" "iPhone 16e" com.apple.CoreSimulator.SimRuntime.iOS-26-3
#   xcrun simctl create "iPhone 16e (Driver)"  "iPhone 16e" com.apple.CoreSimulator.SimRuntime.iOS-26-3
#
# To add an r3, copy the r1 block + create a matching "(Rider C)" sim.
r1: SIM_NAME = $(RIDER_A_SIM)
r1: APP_DIR  = app
r1: ## Run rider app on Rider A simulator
r1: run-sim

r2: SIM_NAME = $(RIDER_B_SIM)
r2: APP_DIR  = app
r2: ## Run rider app on Rider B simulator
r2: run-sim

d1: SIM_NAME = $(DRIVER_SIM)
d1: APP_DIR  = driver
d1: ## Run driver app on Driver simulator
d1: run-sim

# Shared recipe — looks up the simulator by name, boots it if needed,
# and `flutter run`s the right app dir against its UDID. The "(name) ("
# grep filter keeps "iPhone 16e (Rider A)" from matching "iPhone 16e".
run-sim:
	@LINE=$$(xcrun simctl list devices | grep -F "$(SIM_NAME) (" | head -1); \
	if [ -z "$$LINE" ]; then \
	  echo "✗ Simulator '$(SIM_NAME)' not found."; \
	  echo "  Create it with:"; \
	  echo "    xcrun simctl create \"$(SIM_NAME)\" \"iPhone 16e\" \\"; \
	  echo "      com.apple.CoreSimulator.SimRuntime.iOS-26-3"; \
	  exit 1; \
	fi; \
	UDID=$$(echo "$$LINE" | grep -oE '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}' | head -1); \
	if ! echo "$$LINE" | grep -q "(Booted)"; then \
	  echo "↻ Booting $(SIM_NAME)…"; \
	  xcrun simctl boot "$$UDID" 2>/dev/null || true; \
	  open -a Simulator; \
	fi; \
	echo "📍 Setting location to ($(LAT), $(LNG)) so the app isn't in Cupertino"; \
	xcrun simctl location "$$UDID" set "$(LAT),$(LNG)" 2>/dev/null || true; \
	echo "→ flutter run on $(SIM_NAME) ($$UDID)"; \
	cd $(APP_DIR) && flutter run -d $$UDID \
	  --dart-define=API_BASE_URL=http://localhost:4000

# -----------------------------------------------------------------------------
# Simulator GPS overrides
# -----------------------------------------------------------------------------
# iOS simulators don't follow the Mac's actual GPS — they have their own
# Core Location stack. `xcrun simctl location` injects coords directly into
# the running sim so Geolocator (rider's pickup picker, driver's
# LocationPushService) reports them.
#
# Default: all three sims to the same point (Indiranagar, Bangalore).
# Override per-call:
#   make loc LAT=12.9352 LNG=77.6245                # Koramangala
#   make loc-d1 LAT=12.97 LNG=77.59                 # only the driver
#
# Reset to Simulator defaults:
#   make loc-clear
#
# Tip: when testing the matching engine, set both riders to nearby
# coords (~500m apart) and the driver to within ~2 km. The 2dsphere
# query needs all three to share rough geography.
loc: set-sim-location ## Set ALL three sims to (LAT, LNG) — defaults to Bangalore
	@echo "✓ all three sims now report ($(LAT), $(LNG))"

loc-r1: SIM_NAME = $(RIDER_A_SIM)
loc-r1: ## Set Rider A simulator GPS to (LAT, LNG)
loc-r1: set-one-sim-location

loc-r2: SIM_NAME = $(RIDER_B_SIM)
loc-r2: ## Set Rider B simulator GPS to (LAT, LNG)
loc-r2: set-one-sim-location

loc-d1: SIM_NAME = $(DRIVER_SIM)
loc-d1: ## Set Driver simulator GPS to (LAT, LNG)
loc-d1: set-one-sim-location

loc-clear: ## Clear injected GPS on all three sims
	@for SIM in "$(RIDER_A_SIM)" "$(RIDER_B_SIM)" "$(DRIVER_SIM)"; do \
	  UDID=$$(xcrun simctl list devices | grep -F "$$SIM (" | head -1 \
	    | grep -oE '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}' | head -1); \
	  [ -z "$$UDID" ] && { echo "✗ $$SIM not found"; continue; }; \
	  xcrun simctl location "$$UDID" clear 2>/dev/null || true; \
	  echo "✓ $$SIM cleared"; \
	done

# Internal: push (LAT, LNG) to all three sims.
set-sim-location:
	@for SIM in "$(RIDER_A_SIM)" "$(RIDER_B_SIM)" "$(DRIVER_SIM)"; do \
	  UDID=$$(xcrun simctl list devices | grep -F "$$SIM (" | head -1 \
	    | grep -oE '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}' | head -1); \
	  if [ -z "$$UDID" ]; then echo "✗ $$SIM not found — skipping"; continue; fi; \
	  xcrun simctl location "$$UDID" set "$(LAT),$(LNG)"; \
	done

# Internal: push (LAT, LNG) to ONE named sim via $(SIM_NAME).
set-one-sim-location:
	@UDID=$$(xcrun simctl list devices | grep -F "$(SIM_NAME) (" | head -1 \
	  | grep -oE '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}' | head -1); \
	if [ -z "$$UDID" ]; then \
	  echo "✗ Simulator '$(SIM_NAME)' not found"; exit 1; \
	fi; \
	xcrun simctl location "$$UDID" set "$(LAT),$(LNG)"; \
	echo "✓ $(SIM_NAME) now reports ($(LAT), $(LNG))"

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

#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"

    case "$key" in
      API_BASE_URL|GOOGLE_MAPS_KEY|MSG91_WIDGET_ID|MSG91_WIDGET_AUTH_TOKEN|MSG91_AUTH_TOKEN|MSG91_TOKEN_AUTH|ADMOB_REWARDED_AD_UNIT_IOS)
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        if [[ -z "${!key:-}" ]]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < "$env_file"
}

load_env_file ".env"

API_BASE_URL="${API_BASE_URL:-https://sharecab-backend-bbxdisvagq-el.a.run.app}"
MSG91_WIDGET_AUTH_TOKEN="${MSG91_WIDGET_AUTH_TOKEN:-${MSG91_AUTH_TOKEN:-${MSG91_TOKEN_AUTH:-}}}"
export MSG91_WIDGET_AUTH_TOKEN

case "$API_BASE_URL" in
  ""|http://localhost:*|https://localhost:*|http://127.0.0.1:*|https://127.0.0.1:*|http://10.0.2.2:*|https://10.0.2.2:*)
    echo "Refusing to prepare archive with local API_BASE_URL: $API_BASE_URL" >&2
    exit 1
    ;;
esac

if [[ "$API_BASE_URL" != https://* ]]; then
  echo "TestFlight API_BASE_URL must be HTTPS: $API_BASE_URL" >&2
  exit 1
fi

if [[ -z "${MSG91_WIDGET_ID:-}" || -z "${MSG91_WIDGET_AUTH_TOKEN:-}" ]]; then
  echo "MSG91 widget dart-defines are required for TestFlight archives." >&2
  echo "Set MSG91_WIDGET_ID and MSG91_WIDGET_AUTH_TOKEN in app/.env or export them before archiving." >&2
  exit 1
fi

IOS_BUILD_NUMBER="${IOS_BUILD_NUMBER:-$(date -u +%y%m%d%H%M%S)00}"
export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$FLUTTER_BIN" ]]; then
  echo "Could not find flutter. Set FLUTTER_BIN=/path/to/flutter or add Flutter to PATH." >&2
  exit 1
fi

"$FLUTTER_BIN" pub get

flutter_args=(
  build ios
  --release
  --config-only
  --dart-define="API_BASE_URL=$API_BASE_URL"
  --dart-define="MSG91_WIDGET_ID=$MSG91_WIDGET_ID"
  --dart-define="MSG91_WIDGET_AUTH_TOKEN=$MSG91_WIDGET_AUTH_TOKEN"
  --build-number "$IOS_BUILD_NUMBER"
)

add_dart_define() {
  local name="$1"
  local value="${!name:-}"
  if [[ -n "$value" ]]; then
    flutter_args+=(--dart-define="$name=$value")
  fi
}

add_dart_define "GOOGLE_MAPS_KEY"
add_dart_define "ADMOB_REWARDED_AD_UNIT_IOS"

"$FLUTTER_BIN" "${flutter_args[@]}"

generated="ios/Flutter/Generated.xcconfig"
defines="$(grep '^DART_DEFINES=' "$generated" | cut -d= -f2- || true)"

if [[ -z "$defines" ]]; then
  echo "DART_DEFINES missing from $generated" >&2
  exit 1
fi

decoded="$(mktemp)"
trap 'rm -f "$decoded"' EXIT
: > "$decoded"

IFS=',' read -ra encoded_items <<< "$defines"
for encoded in "${encoded_items[@]}"; do
  if [[ -n "$encoded" ]]; then
    printf '%s' "$encoded" | base64 --decode >> "$decoded" 2>/dev/null || \
      printf '%s' "$encoded" | base64 -D >> "$decoded"
    printf '\n' >> "$decoded"
  fi
done

compiled_api_base="$(grep '^API_BASE_URL=' "$decoded" | tail -n 1 | cut -d= -f2- || true)"
compiled_msg91_widget_id="$(grep '^MSG91_WIDGET_ID=' "$decoded" | tail -n 1 | cut -d= -f2- || true)"
compiled_msg91_auth_token="$(grep '^MSG91_WIDGET_AUTH_TOKEN=' "$decoded" | tail -n 1 | cut -d= -f2- || true)"

if [[ "$compiled_api_base" != "$API_BASE_URL" ]]; then
  echo "Generated iOS config has wrong API_BASE_URL." >&2
  echo "Expected: $API_BASE_URL" >&2
  echo "Actual:   $compiled_api_base" >&2
  exit 1
fi

if [[ -z "$compiled_msg91_widget_id" || -z "$compiled_msg91_auth_token" ]]; then
  echo "Generated iOS config is missing MSG91 widget dart-defines." >&2
  exit 1
fi

echo "iOS manual archive config ready."
echo "API_BASE_URL=$compiled_api_base"
echo "MSG91 widget config=present"
echo "IOS_BUILD_NUMBER=$IOS_BUILD_NUMBER"
echo "Now open app/ios/Runner.xcworkspace in Xcode and use Product > Archive."

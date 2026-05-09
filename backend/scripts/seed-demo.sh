#!/usr/bin/env bash
# Seed the 3 demo accounts (R1, R2, Driver) and bring the driver online.
# Idempotent: existing accounts return 409 from /api/auth/signup and we treat
# that as success.
#
# Override the API root with API_URL (default http://localhost:4000).
set -euo pipefail

API_URL="${API_URL:-http://localhost:4000}"

# ---------------------------------------------------------------------------
# Wait for the backend to be reachable. Gives nodemon up to 30s to come up.
# ---------------------------------------------------------------------------
printf "→ waiting for %s/health" "$API_URL"
for i in {1..30}; do
  if curl -sf "$API_URL/health" >/dev/null 2>&1; then
    echo " ready"
    break
  fi
  printf "."
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo
    echo "✗ backend not reachable at $API_URL after 30s — is \`make dev\` running?"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Idempotent signup helper. 201 = created; 409 = already exists; anything
# else is a hard fail.
# ---------------------------------------------------------------------------
seed() {
  local label="$1"; shift
  local body="$1"; shift
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/api/auth/signup" \
    -H 'Content-Type: application/json' -d "$body")
  case "$code" in
    201) echo "  $label: created" ;;
    409) echo "  $label: already exists" ;;
    *)   echo "  $label: HTTP $code (unexpected)"; exit 1 ;;
  esac
}

echo "→ seeding demo accounts"
seed "Rider 1   (9990000101)" \
  '{"name":"Demo Rider One","phone":"9990000101","password":"demo1234","role":"rider"}'
seed "Rider 2   (9990000102)" \
  '{"name":"Demo Rider Two","phone":"9990000102","password":"demo1234","role":"rider"}'
seed "Driver    (9990000103)" \
  '{"name":"Demo Driver","phone":"9990000103","password":"demo1234","role":"driver","driver":{"licenseNumber":"DEMO-DL","vehicle":{"model":"Toyota Innova","plate":"DEMO1234","color":"silver","capacity":6}}}'

# ---------------------------------------------------------------------------
# Bring the driver online and park at HSR Layout.
# ---------------------------------------------------------------------------
echo "→ bringing driver online at HSR Layout"
DRIVER_TOKEN=$(curl -sf -X POST "$API_URL/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9990000103","password":"demo1234"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')

curl -sf -X POST "$API_URL/api/drivers/online" \
  -H "Authorization: Bearer $DRIVER_TOKEN" >/dev/null
curl -sf -X POST "$API_URL/api/drivers/location" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $DRIVER_TOKEN" \
  -d '{"lat":12.9148,"lng":77.6764}' >/dev/null
echo "  online at (12.9148, 77.6764)"

cat <<EOF

✓ Demo credentials (OTP 123456 for all riders):
    Rider 1   phone 9990000101
    Rider 2   phone 9990000102
    Driver    phone 9990000103   password demo1234
EOF

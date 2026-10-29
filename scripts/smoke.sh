#!/usr/bin/env bash
# End-to-end check of the gateway against a stand-in upstream.
#
#   ./scripts/smoke.sh
#
# Starts the mock upstream on 9001 and a throwaway Bamboo on 8799, walks a
# customer from registration to a billed request on all three protocols,
# then tears both processes down. Exits non-zero on the first failure.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${SMOKE_PORT:-8799}"
UPSTREAM_PORT="${SMOKE_UPSTREAM_PORT:-9001}"
DATA="$(mktemp -d)/smoke.json"
LOG="$(mktemp)"
PASS=0
FAIL=0

: "${BUN_LANG_HOME:=$ROOT/../Bun/bun}"

cleanup() {
  [ -n "${BAMBOO_PID:-}" ] && kill "$BAMBOO_PID" 2>/dev/null
  [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf '  ok    %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      printf '  ok    %s\n' "$label"
      PASS=$((PASS + 1))
      ;;
    *)
      printf '  FAIL  %s (missing %s)\n' "$label" "$needle"
      FAIL=$((FAIL + 1))
      ;;
  esac
}

echo "Bamboo-api smoke test"
echo

python3 scripts/mock_upstream.py >"$LOG.mock" 2>&1 &
MOCK_PID=$!
sleep 1

PORT="$PORT" \
DATA_FILE="$DATA" \
UPSTREAM_BASE_URL="http://127.0.0.1:$UPSTREAM_PORT/v1" \
UPSTREAM_API_KEY="smoke-key" \
ADMIN_EMAIL="admin@smoke.test" \
ADMIN_PASSWORD="smoke-admin-pass" \
BUN_LANG_HOME="$BUN_LANG_HOME" \
  ./bin/bamboo app.bun >"$LOG" 2>&1 &
BAMBOO_PID=$!

for _ in $(seq 1 40); do
  if curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/login"; then break; fi
  sleep 0.5
done

BASE="http://127.0.0.1:$PORT"
CUSTOMER_JAR="$(mktemp)"
ADMIN_JAR="$(mktemp)"

echo "auth"
status=$(curl -s -o /dev/null -w '%{http_code}' -c "$CUSTOMER_JAR" -X POST "$BASE/api/auth/register" \
  -H 'content-type: application/json' \
  -d '{"name":"Smoke","email":"smoke@example.com","password":"smoke-password"}')
check "register a customer" "201" "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/register" \
  -H 'content-type: application/json' \
  -d '{"name":"Smoke","email":"smoke@example.com","password":"smoke-password"}')
check "duplicate email is refused" "400" "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -b "$CUSTOMER_JAR" "$BASE/dashboard")
check "dashboard renders for a session" "200" "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/dashboard")
check "dashboard redirects without a session" "302" "$status"

echo
echo "admin"
status=$(curl -s -o /dev/null -w '%{http_code}' -c "$ADMIN_JAR" -X POST "$BASE/api/admin/login" \
  -H 'content-type: application/json' \
  -d '{"email":"admin@smoke.test","password":"smoke-admin-pass"}')
check "admin signs in" "200" "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/admin/models/import" -b "$ADMIN_JAR")
check "catalogue imports from the upstream" "200" "$status"

models=$(curl -s -b "$ADMIN_JAR" "$BASE/api/admin/models")
contains "imported gpt/4o-mini" "gpt/4o-mini" "$models"
contains "imported claude/sonnet-5" "claude/sonnet-5" "$models"
contains "imported a free model" "free/llama-3-8b" "$models"

USER_ID=$(curl -s -b "$CUSTOMER_JAR" "$BASE/api/me" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
status=$(curl -s -o /dev/null -w '%{http_code}' -b "$ADMIN_JAR" -X POST "$BASE/api/admin/users/$USER_ID/credit" \
  -H 'content-type: application/json' -d '{"dollars":5}')
check "admin credits a wallet" "200" "$status"

echo
echo "keys"
KEY=$(curl -s -b "$CUSTOMER_JAR" -X POST "$BASE/api/keys" \
  -H 'content-type: application/json' -d '{"name":"smoke"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])')
case "$KEY" in
  bk_live_*) check "key has the expected shape" "yes" "yes" ;;
  *) check "key has the expected shape" "yes" "no" ;;
esac

status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/v1/models")
check "models refuses an anonymous caller" "401" "$status"

status=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$BASE/v1/models")
check "models accepts the key" "200" "$status"

echo
echo "chat"
body=$(curl -s -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/chat/completions" \
  -d '{"model":"gpt/4o-mini","messages":[{"role":"user","content":"hello"}]}')
contains "chat answers" "echo: hello" "$body"
contains "chat reports usage" "prompt_tokens" "$body"

stream=$(curl -sN -m 20 -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/chat/completions" \
  -d '{"model":"gpt/4o-mini","stream":true,"messages":[{"role":"user","content":"hello"}]}')
contains "stream sends events" "data: " "$stream"
contains "stream terminates" "[DONE]" "$stream"
contains "stream carries text" "ledger" "$stream"

echo
echo "messages"
message=$(curl -s -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/messages" \
  -d '{"model":"claude/sonnet-5","max_tokens":64,"messages":[{"role":"user","content":"hello"}]}')
contains "messages answers in the anthropic shape" '"type": "message"' "$message"
contains "messages reports usage" "input_tokens" "$message"

mstream=$(curl -sN -m 20 -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/messages" \
  -d '{"model":"claude/sonnet-5","max_tokens":64,"stream":true,"messages":[{"role":"user","content":"hello"}]}')
contains "messages stream starts a message" "message_start" "$mstream"
contains "messages stream ends a message" "message_stop" "$mstream"

echo
echo "responses"
response=$(curl -s -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/responses" -d '{"model":"gpt/4o-mini","input":"hello"}')
contains "responses answers in the responses shape" '"object": "response"' "$response"
contains "responses has output text" "output_text" "$response"

echo
echo "billing"
balance=$(curl -s -H "Authorization: Bearer $KEY" "$BASE/v1/balance")
contains "balance is reported" '"balance"' "$balance"

spent=$(python3 - "$balance" <<'PY'
import json, sys
print("yes" if json.loads(sys.argv[1])["key"]["spent"] > 0 else "no")
PY
)
check "requests were charged" "yes" "$spent"

free=$(curl -s -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/chat/completions" \
  -d '{"model":"free/llama-3-8b","messages":[{"role":"user","content":"free please"}]}')
contains "free model answers" "echo: free please" "$free"

echo
echo "errors"
body=$(curl -s -H "Authorization: Bearer bk_live_nope" "$BASE/v1/models")
contains "an unknown key is rejected" "Invalid API key" "$body"

body=$(curl -s -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -X POST "$BASE/v1/chat/completions" -d '{"model":"nope/unknown","messages":[]}')
contains "an unknown model is rejected" "model_not_found" "$body"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

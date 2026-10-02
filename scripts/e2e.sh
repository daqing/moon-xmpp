#!/usr/bin/env bash
# Integration test against the local ejabberd (T9.3).
# Requires the container from scripts/ejabberd.sh. Verifies both directions:
#   alice -> bob  (bob is online: direct delivery)
#   bob -> alice  (alice is offline: mod_offline stores it, delivered when
#                  alice connects)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'kill "${BOB_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT

"$ROOT/scripts/prosody.sh" start >/dev/null
# registration is idempotent for the test: re-registering an existing
# account may fail, which is fine
"$ROOT/scripts/prosody.sh" register alice secret123 >/dev/null 2>&1 || true
"$ROOT/scripts/prosody.sh" register bob secret123 >/dev/null 2>&1 || true

(cd "$ROOT" && "$HOME/.moon/bin/moon" build cmd/main >/dev/null)
BIN="$(find "$ROOT/_build" -type f -name 'main.exe' -path '*cmd/main*' -not -path '*test*' -not -path '*.dSYM*' | head -1)"
CA="$ROOT/core/testdata/test_cert.pem"

"$BIN" \
  --jid bob@localhost --password secret123 \
  --to alice@localhost --body "ping" \
  --ca-file "$CA" >"$TMP/bob.out" 2>&1 &
BOB_PID=$!
sleep 3

timeout 25 "$BIN" \
  --jid alice@localhost --password secret123 \
  --to bob@localhost --body "integration hello" \
  --ca-file "$CA" >"$TMP/alice.out" 2>&1 || true

kill "$BOB_PID" 2>/dev/null || true
sleep 1

FAIL=0
if grep -q "\[alice@localhost/.*\] integration hello" "$TMP/bob.out"; then
  echo "PASS: bob received the message from alice (online delivery)"
else
  echo "FAIL: bob did not receive the message; bob.out:"
  cat "$TMP/bob.out"
  FAIL=1
fi
if grep -q "\[bob@localhost/.*\] ping" "$TMP/alice.out"; then
  echo "PASS: alice received the stored message from bob (offline delivery)"
else
  echo "FAIL: alice did not receive the stored message; alice.out:"
  cat "$TMP/alice.out"
  FAIL=1
fi
exit "$FAIL"

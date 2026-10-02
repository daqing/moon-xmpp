#!/usr/bin/env bash
# Third-party interop test (T9.4, automated equivalent): alice runs on
# slixmpp — an independent Python XMPP implementation — inside a container,
# while bob is our CLI. Verifies:
#   bob -> alice  "Hello from MoonBit!" arrives at the third-party client
#   alice -> bob  "pong from slixmpp" arrives at our CLI
# Transcripts are stored in docs/acceptance/ as evidence.
set -euo pipefail

NAME="moon-xmpp-slixmpp"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="$ROOT/docs/acceptance"
mkdir -p "$EVIDENCE"
TMP="$(mktemp -d)"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

"$ROOT/scripts/prosody.sh" start >/dev/null
"$ROOT/scripts/prosody.sh" register alice secret123 >/dev/null 2>&1 || true
"$ROOT/scripts/prosody.sh" register bob secret123 >/dev/null 2>&1 || true

docker build -f "$ROOT/docker/slixmpp.Dockerfile" \
  -t moon-xmpp-slixmpp "$ROOT/docker" >/dev/null
docker rm -f "$NAME" >/dev/null 2>&1 || true

(cd "$ROOT" && "$HOME/.moon/bin/moon" build cmd/main >/dev/null)
BIN="$(find "$ROOT/_build" -type f -name 'main.exe' -path '*cmd/main*' -not -path '*test*' -not -path '*.dSYM*' | head -1)"
CA="$ROOT/core/testdata/test_cert.pem"

# alice (third-party client) waits for bob's message and replies
docker run -d --name "$NAME" \
  --network host \
  -v "$ROOT/docker/slixmpp_alice.py":/alice.py:ro \
  -v "$ROOT/core/testdata/test_cert.pem":/certs/test_cert.pem:ro \
  moon-xmpp-slixmpp python /alice.py >"$TMP/alice.out" 2>&1
sleep 5

# bob (our CLI) sends the acceptance message; his receive loop captures the
# slixmpp reply and ends when the stream closes
timeout 60 "$BIN" \
  --jid bob@localhost --password secret123 \
  --to alice@localhost --body "Hello from MoonBit!" \
  --ca-file "$CA" >"$TMP/bob.out" 2>&1 || true
sleep 2

docker logs "$NAME" >"$TMP/alice.full" 2>&1 || true
cp "$TMP/bob.out" "$EVIDENCE/interop-bob-cli.txt"
cp "$TMP/alice.full" "$EVIDENCE/interop-alice-slixmpp.txt"

FAIL=0
if grep -q "Hello from MoonBit!" "$TMP/alice.full"; then
  echo "PASS: the third-party client received 'Hello from MoonBit!'"
else
  echo "FAIL: third-party client output:"
  cat "$TMP/alice.full"
  FAIL=1
fi
if grep -q "\[alice@localhost/.*\] pong from slixmpp" "$TMP/bob.out"; then
  echo "PASS: our CLI received the third-party client's reply"
else
  echo "FAIL: our CLI output:"
  cat "$TMP/bob.out"
  FAIL=1
fi
exit "$FAIL"

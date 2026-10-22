#!/usr/bin/env bash
# Roster and presence-subscription acceptance run (T10).
#
# alice runs on slixmpp (an independent Python XMPP implementation) inside a
# container; bob is our CLI. Verifies:
#   bob's roster get returns alice with subscription "both"
#   bob's inbound subscription request from alice is surfaced, not auto-answered
#   bob receives alice's presence broadcast once authorization is mutual
# Transcripts are stored in docs/acceptance/ as evidence.
set -euo pipefail

NAME="moon-xmpp-slixmpp-roster"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="$ROOT/docs/acceptance"
mkdir -p "$EVIDENCE"
TMP="$(mktemp -d)"
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Deleting is not allowed here: park the raw transcripts instead.
  mkdir -p /Users/daqing/protected/tmp
  mv "$TMP" \
    "/Users/daqing/protected/tmp/$(date +%Y%m%d-%H%M%S)-moon-xmpp-roster-run" \
    2>/dev/null || true
}
trap cleanup EXIT

# Fresh container: roster and subscription state persist in the container,
# so a previous run would already be subscribed and produce no request.
"$ROOT/scripts/prosody.sh" stop >/dev/null 2>&1 || true
"$ROOT/scripts/prosody.sh" start >/dev/null
"$ROOT/scripts/prosody.sh" register alice secret123 >/dev/null 2>&1 || true
"$ROOT/scripts/prosody.sh" register bob secret123 >/dev/null 2>&1 || true

docker build -f "$ROOT/docker/slixmpp.Dockerfile" \
  -t moon-xmpp-slixmpp "$ROOT/docker" >/dev/null
docker rm -f "$NAME" >/dev/null 2>&1 || true

(cd "$ROOT" && "$HOME/.moon/bin/moon" build cmd/main >/dev/null)
BIN="$(find "$ROOT/_build" -type f -name 'main.exe' -path '*cmd/main*' -not -path '*test*' -not -path '*.dSYM*' | head -1)"
CA="$ROOT/core/testdata/test_cert.pem"

# alice (third-party client) publishes presence, subscribes to bob, and
# approves bob's request
docker run -d --name "$NAME" \
  --network host \
  -v "$ROOT/docker/slixmpp_alice_roster.py":/alice.py:ro \
  -v "$ROOT/core/testdata/test_cert.pem":/certs/test_cert.pem:ro \
  moon-xmpp-slixmpp python /alice.py >"$TMP/alice.out" 2>&1
sleep 5

# run 1: bob asks to see alice's presence and grants alice's request, then
# stays online long enough for the authorization exchange to settle
timeout 12 "$BIN" \
  --jid bob@localhost --password secret123 \
  --subscribe alice@localhost --approve alice@localhost \
  --ca-file "$CA" >"$TMP/bob-subscribe.out" 2>&1 || true
sleep 3

# run 2: a fresh session fetches the roster and goes online, so alice's
# presence broadcast is delivered to it
timeout 15 "$BIN" \
  --jid bob@localhost --password secret123 \
  --roster \
  --ca-file "$CA" >"$TMP/bob-roster.out" 2>&1 || true
sleep 2

docker logs "$NAME" >"$TMP/alice.full" 2>&1 || true
cp "$TMP/bob-subscribe.out" "$EVIDENCE/roster-bob-subscribe.txt"
cp "$TMP/bob-roster.out" "$EVIDENCE/roster-bob-fetch.txt"
cp "$TMP/alice.full" "$EVIDENCE/roster-alice-slixmpp.txt"

FAIL=0
if grep -q "subscription Subscribe from alice@localhost" "$TMP/bob-subscribe.out"; then
  echo "PASS: bob surfaced alice's inbound subscription request"
else
  echo "FAIL: no inbound subscription request seen; bob output:"
  cat "$TMP/bob-subscribe.out"
  FAIL=1
fi
if grep -q "alice@localhost name=\"\" subscription=SubBoth" "$TMP/bob-roster.out"; then
  echo "PASS: bob's roster lists alice with subscription both"
else
  echo "FAIL: roster did not show a mutual subscription; bob output:"
  cat "$TMP/bob-roster.out"
  FAIL=1
fi
if grep -q "alice@localhost/.* is available" "$TMP/bob-roster.out"; then
  echo "PASS: bob received alice's presence broadcast"
else
  echo "FAIL: no presence broadcast from alice; bob output:"
  cat "$TMP/bob-roster.out"
  FAIL=1
fi
if grep -q "alice sees bob@localhost" "$TMP/alice.full"; then
  echo "PASS: alice (slixmpp) received bob's presence broadcast"
else
  echo "FAIL: slixmpp saw no presence from bob; alice output:"
  cat "$TMP/alice.full"
  FAIL=1
fi
exit "$FAIL"

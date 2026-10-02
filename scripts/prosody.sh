#!/usr/bin/env bash
# Local Prosody test environment for moon-xmpp (native arm64 alternative to
# the ejabberd container, whose image crashes its c2s acceptor under amd64
# emulation on Apple Silicon).
#   scripts/prosody.sh start              build the image if needed and start
#   scripts/prosody.sh stop               stop and remove the container
#   scripts/prosody.sh register USER PASS register USER@localhost with PASS
set -euo pipefail

NAME="moon-xmpp-prosody"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
  start)
    if docker ps --format '{{.Names}}' | grep -q "^$NAME$"; then
      echo "prosody is already running on 127.0.0.1:5222"
      exit 0
    fi
    mkdir -p "$ROOT/docker/certs"
    cat "$ROOT/core/testdata/test_cert.pem" "$ROOT/core/testdata/test_key.pem" \
      > "$ROOT/docker/certs/server.pem"
    docker build -f "$ROOT/docker/prosody.Dockerfile" \
      -t moon-xmpp-prosody "$ROOT/docker" >/dev/null
    docker run -d --name "$NAME" \
      -p 5222:5222 \
      -v "$ROOT/docker/prosody.cfg.lua":/etc/prosody/prosody.cfg.lua:ro \
      -v "$ROOT/docker/certs":/etc/prosody/certs:ro \
      moon-xmpp-prosody
    echo "waiting for the client port..."
    for _ in $(seq 1 60); do
      if nc -z 127.0.0.1 5222 2>/dev/null; then
        echo "prosody is up on 127.0.0.1:5222 (STARTTLS required, host: localhost)"
        exit 0
      fi
      if ! docker ps --format '{{.Names}}' | grep -q "^$NAME$"; then
        echo "container exited unexpectedly; last logs:"
        docker logs "$NAME" 2>&1 | tail -20 || true
        exit 1
      fi
      sleep 1
    done
    echo "prosody did not open port 5222 in time; last logs:"
    docker logs "$NAME" 2>&1 | tail -20 || true
    exit 1
    ;;
  stop)
    docker stop "$NAME" 2>/dev/null || true
    docker rm "$NAME" 2>/dev/null || true
    echo "prosody stopped"
    ;;
  register)
    docker exec "$NAME" prosodyctl --config /etc/prosody/prosody.cfg.lua \
      register "$2" localhost "$3"
    echo "registered $2@localhost"
    ;;
  *)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac

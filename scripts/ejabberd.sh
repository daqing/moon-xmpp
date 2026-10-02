#!/usr/bin/env bash
# Local ejabberd test environment for moon-xmpp (T9.1).
#   scripts/ejabberd.sh start              start the container, wait for port 5222
#   scripts/ejabberd.sh stop               stop and remove the container
#   scripts/ejabberd.sh register USER PASS register USER@localhost with PASS
set -euo pipefail

NAME="moon-xmpp-ejabberd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
  start)
    mkdir -p "$ROOT/docker/certs"
    cat "$ROOT/core/testdata/test_cert.pem" "$ROOT/core/testdata/test_key.pem" \
      > "$ROOT/docker/certs/server.pem"
    docker run -d --name "$NAME" --platform linux/amd64 \
      -p 5222:5222 \
      -v "$ROOT/docker/ejabberd.yml":/home/ejabberd/conf/ejabberd.yml:ro \
      -v "$ROOT/docker/certs":/home/ejabberd/conf/certs:ro \
      ejabberd/ecs:latest
    echo "waiting for the client port..."
    for _ in $(seq 1 60); do
      if nc -z 127.0.0.1 5222 2>/dev/null; then
        echo "ejabberd is up on 127.0.0.1:5222 (STARTTLS required, host: localhost)"
        exit 0
      fi
      if ! docker ps --format '{{.Names}}' | grep -q "^$NAME$"; then
        echo "container exited unexpectedly; last logs:"
        docker logs "$NAME" 2>&1 | tail -20 || true
        exit 1
      fi
      sleep 1
    done
    echo "ejabberd did not open port 5222 in time; last logs:"
    docker logs "$NAME" 2>&1 | tail -20 || true
    exit 1
    ;;
  stop)
    docker stop "$NAME" 2>/dev/null || true
    docker rm "$NAME" 2>/dev/null || true
    echo "ejabberd stopped"
    ;;
  register)
    docker exec "$NAME" ejabberdctl register "$2" localhost "$3"
    echo "registered $2@localhost"
    ;;
  *)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac

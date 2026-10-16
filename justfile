e2e:
  bash scripts/prosody.sh stop
  bash scripts/prosody.sh start
  bash scripts/e2e.sh
  bash scripts/prosody.sh stop

# Sync the version across VERSION, moon.mod, moon-xmpp.mbt and moon-xmpp_test.mbt
bump version:
  #!/usr/bin/env bash
  set -euo pipefail
  cd "{{justfile_directory()}}"

  new="{{version}}"
  if ! printf '%s' "$new" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "expected a version like 0.12.0, got: $new" >&2
    exit 1
  fi

  old="$(sed -n 's/^version = "\(.*\)"$/\1/p' moon.mod)"
  if [ -z "$old" ]; then
    echo "could not read the version from moon.mod" >&2
    exit 1
  fi

  if [ "$old" = "$new" ]; then
    echo "already at $new"
    exit 0
  fi

  esc="$(printf '%s' "$old" | sed 's/\./\\./g')"
  for file in moon.mod moon-xmpp.mbt moon-xmpp_test.mbt; do
    tmp="$(mktemp)"
    sed "s/$esc/$new/g" "$file" >"$tmp"
    mv "$tmp" "$file"
  done
  printf 'v%s\n' "$new" >VERSION

  echo "bumped $old -> $new"
  git --no-pager diff --stat VERSION moon.mod moon-xmpp.mbt moon-xmpp_test.mbt

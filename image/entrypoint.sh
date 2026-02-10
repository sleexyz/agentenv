# Entrypoint for agentenv container image
# Invoked as: /busybox sh /entrypoint.sh [args...]
# Uses /busybox for all operations until /nix is seeded and real binaries are available

# Auto-seed /nix from backup if volume is empty (first run)
if [ ! -d /nix/store ] || [ -z "$(/busybox ls -A /nix/store 2>/dev/null)" ]; then
  echo "agentenv: seeding /nix from backup (first run)..."
  /busybox cp -a /nix-seed/* /nix/
  echo "agentenv: seed complete."
fi

# Activate profile if mounted
if [ -n "${AGENTENV_PROFILE:-}" ] && [ -f "$AGENTENV_PROFILE/activate.sh" ]; then
  echo "agentenv: activating profile from $AGENTENV_PROFILE..."
  /bin/sh "$AGENTENV_PROFILE/activate.sh"
fi

# Generate wrappers for installed repos
if [ -d /installed ]; then
  /busybox mkdir -p /usr/local/bin
  for repo in /installed/*/; do
    [ -d "${repo}bin" ] || continue
    name=$(/busybox basename "$repo")
    has_flake=false
    [ -f "${repo}flake.nix" ] && has_flake=true

    for bin in "${repo}bin"/*; do
      [ -f "$bin" ] && [ -x "$bin" ] || continue
      cmd=$(/busybox basename "$bin")
      wrapper="/usr/local/bin/$cmd"
      if $has_flake; then
        echo "#!/bin/sh" > "$wrapper"
        echo "exec nix develop /installed/$name --command /installed/$name/bin/$cmd \"\$@\"" >> "$wrapper"
      else
        echo "#!/bin/sh" > "$wrapper"
        echo "exec /installed/$name/bin/$cmd \"\$@\"" >> "$wrapper"
      fi
      /busybox chmod +x "$wrapper"
    done
  done
fi

cd /work

# If arguments were passed, run them (inside nix develop if flake exists)
if [ $# -gt 0 ]; then
  if [ -f /work/flake.nix ]; then
    exec nix develop --command "$@"
  else
    exec "$@"
  fi
fi

# Default: enter nix dev shell if flake.nix exists, otherwise interactive bash
if [ -f /work/flake.nix ]; then
  exec nix develop
else
  exec /bin/sh
fi

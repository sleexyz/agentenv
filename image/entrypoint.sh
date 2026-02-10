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

cd /work

# If arguments were passed, run them directly (now that /nix is populated)
if [ $# -gt 0 ]; then
  exec "$@"
fi

# Default: enter nix dev shell if flake.nix exists, otherwise interactive bash
if [ -f /work/flake.nix ]; then
  exec nix develop
else
  exec /bin/sh
fi

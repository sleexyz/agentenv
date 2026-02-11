# Entrypoint for agentenv container image
# Invoked as: /busybox sh /entrypoint.sh [args...]
# Uses /busybox for all operations until /nix is seeded and real binaries are available

# Auto-seed /nix from backup if volume is empty (first run)
if [ ! -d /nix/store ] || [ -z "$(/busybox ls -A /nix/store 2>/dev/null)" ]; then
  echo "agentenv: seeding /nix from backup (first run)..."
  /busybox cp -a /nix-seed/* /nix/
  echo "agentenv: seed complete."
fi

# Fix HOME — nixos/nix image sets HOME=/ but root's home is /root
export HOME=/root

# Ensure nix profile binaries are on PATH (before shell detection)
export PATH="$HOME/.nix-profile/bin:$PATH"

# Install personal tools from profile flake (if present)
# First run: clears base image packages, builds and installs (slow, persists in golden volume)
# Subsequent runs: no-op (already installed, cached in golden volume)
if [ -n "${AGENTENV_PROFILE:-}" ] && [ -f "$AGENTENV_PROFILE/flake.nix" ]; then
  if ! command -v zsh >/dev/null 2>&1; then
    echo "agentenv: first-time setup — clearing base image packages..."
    for pkg in bash-interactive coreutils-full curl findutils git-minimal \
               gnugrep gnutar gzip iana-etc less man-db openssh wget which; do
      nix profile remove "$pkg" 2>/dev/null || true
    done
    echo "agentenv: installing personal tools from profile flake..."
    if nix profile install "$AGENTENV_PROFILE#portable" 2>&1; then
      echo "agentenv: personal tools installed."
    else
      echo "agentenv: warning: personal tools install failed, continuing without them"
    fi
  fi
fi

# Activate dotfiles (pure symlinks) if profile is mounted
if [ -n "${AGENTENV_PROFILE:-}" ] && [ -f "$AGENTENV_PROFILE/activate.sh" ]; then
  . "$AGENTENV_PROFILE/activate.sh"
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

# Prefer zsh if available (installed by personal tools), fall back to bash
SHELL_CMD="bash"
command -v zsh >/dev/null 2>&1 && SHELL_CMD="zsh"

# Default: enter nix dev shell if flake.nix exists, otherwise interactive shell
if [ -f /work/flake.nix ]; then
  exec nix develop --command "$SHELL_CMD"
else
  exec "$SHELL_CMD"
fi

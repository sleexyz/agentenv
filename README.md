# agentenv

Portable dev environments for agents and humans. Dev shell in ~2s on macOS.

```
$ agentenv .
=== agentenv dev shell ===
hello version: hello (GNU Hello) 2.12.1
jq version: jq-1.7.1
Working directory: /work
==========================
```

## What it does

agentenv gives you a `nix develop` shell instantly by cloning a pre-populated Nix store via APFS copy-on-write. No downloads, no waiting. Optionally layer your personal config (dotfiles, editor setup, skills) on top.

## Prerequisites

- macOS (Apple Silicon)
- [apple/container](https://github.com/apple/container) — `container` binary in PATH
- A project with a `flake.nix`

## Quick start

Build the container image:

```bash
container build -t agentenv image/
```

Run a dev shell:

```bash
./agentenv .                          # current directory
./agentenv path/to/project/           # specific project
./agentenv --profile ~/config .       # with personal profile
```

The first run bootstraps a golden Nix volume (~30s, one-time). Subsequent runs clone it in ~2ms and boot in ~2s.

## Profile support

A profile is a directory with an `activate.sh` at its root. It gets mounted into the container and activated before the dev shell starts.

```
~/config/
  activate.sh               # creates symlinks into the right places
  .config/
    nvim/                    # neovim config
    zsh/                     # shell config
    git/                     # git config
  skills/                    # Claude skills
    polo/SKILL.md
    frontend-design/SKILL.md
```

Example `activate.sh`:

```bash
#!/bin/sh
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.config
ln -sfn "$PROFILE_DIR/.config/nvim" ~/.config/nvim
ln -sfn "$PROFILE_DIR/.config/zsh" ~/.config/zsh
```

### Default profile via config file

Create `~/.config/agentenv/config.toml`:

```toml
profile = "~/config"
```

Then `agentenv .` automatically loads your profile without `--profile`.

## How it works

1. **Golden volume**: A named ext4 volume with a pre-seeded Nix store
2. **APFS COW clone**: `cp -c` clones the golden volume in ~2ms regardless of size
3. **Container boot**: apple/container starts a lightweight Linux VM in ~0.7s
4. **Profile activation**: Optional `activate.sh` symlinks your config into place
5. **nix develop**: Enters the dev shell (~1.3s warm)
6. **Auto-promote**: On exit, the used volume is cloned back to golden, so future sessions inherit any new packages

```
agentenv .
  |
  +-- Clone golden volume (2ms, APFS COW)
  +-- Boot container (0.7s, apple/container)
  +-- Activate profile (optional, <0.1s)
  +-- nix develop (1.3s warm)
  |
  +-- On exit: promote to golden + cleanup
```

Total: **~2s** from command to working dev shell.

### Why APFS COW clones?

| Approach | Warm dev shell | Store provision | Complexity |
|----------|---------------|-----------------|------------|
| Fresh download | ~26s | ~26s | Low |
| OverlayFS | ~2.2s | High (overlay + DB) | High |
| Shared VirtioFS | ~4.1s | VirtioFS mount | Medium |
| **APFS COW clone** | **~1.3s** | **2ms** | **Low** |

The Nix store lives on an ext4 named volume (not VirtioFS), so there's zero file descriptor pressure. APFS clones are instant regardless of store size.

## Usage

```
Usage: agentenv [options] [directory]

Options:
  -p, --profile <dir>   Mount a profile directory (with activate.sh)
  -h, --help            Show this help
```

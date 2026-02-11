---
name: agentenv
description: Guide for agentenv — mutable installations and containerized dev environments. Use when the user wants to install a local project binary on PATH, manage installed repos, launch container dev shells, or work with the agentenv registry.
---

# agentenv

Portable dev environments for agents and humans. Two modes: **mutable installations** (expose local project binaries on PATH) and **container launch** (instant Nix dev shells via APFS COW cloning).

## Mutable installations

Preferred approach for exposing a local project's binary on PATH. No nix rebuild needed.

```bash
cd ~/projects/my-tool && agentenv install
```

This creates a registry symlink (`~/config/installed/my-tool → ~/projects/my-tool`) and generates wrapper scripts in `~/config/bin/` for each executable in the repo's `bin/` directory. Changes to the repo are reflected immediately. Installed repos are also mounted into containers launched by `agentenv`.

### Repo convention

The repo needs a `bin/` directory with executables (direct scripts or symlinks to build outputs):

```
my-tool/
  bin/
    my-tool → ../dist/my-tool    # symlink to build output
  flake.nix                       # optional, for dependency encapsulation
  skills/                         # optional, Claude Code skills
```

### Dependency encapsulation

If the repo has a `flake.nix` with a devShell, the wrapper runs the binary inside `nix develop --command`, so dependencies are encapsulated without polluting the global environment. If no `flake.nix`, the wrapper execs the binary directly.

### Skill linking

If the repo has a `skills/` directory, each subdirectory is symlinked into `~/.claude/skills/` on install. Skills are unlinked on uninstall and regenerated on rewrap.

### Commands

```bash
agentenv install [name]    # install cwd (name defaults to basename)
agentenv uninstall <name>  # remove installation, wrappers, and skill links
agentenv list              # show installed repos
agentenv rewrap            # regenerate all wrappers and skill links
```

### Registry

Single source of truth: `~/config/installed/`. Each entry is a symlink from name to the repo's absolute path.

### Currently installed

Run `agentenv list` to see current state.

## Container launch

Instant Nix dev shell via APFS copy-on-write volume cloning (~2s startup). Requires a `flake.nix` in the target directory.

```bash
agentenv .                          # dev shell with personal profile (~config)
agentenv --no-profile .             # bare dev shell, no profile
agentenv --profile ~/other .        # override profile directory
agentenv project/                   # dev shell for another directory
agentenv . -- make test             # run command non-interactively, exit with its status
agentenv . -t -- htop               # force TTY for interactive commands
```

### How it works

Three independent layers compose at boot:

1. **Nix store** — Golden volume COW-cloned (~2ms). Holds all packages.
2. **Personal tools** — `nix profile install` from profile's `flake.nix` (first boot only, cached in golden volume). Provides zsh, neovim, tmux, ripgrep, etc.
3. **Dev environment** — Profile directory (`~/config`) mounted via VirtioFS. `activate.sh` symlinks dotfiles and skills. Pure symlinks, no nix.
4. **DevShell** — `nix develop` from project's `flake.nix`. Project-specific tools on PATH.
5. On exit, golden volume promoted (persists nix store + personal tools).

First boot: ~3-4 min (downloads personal tools). Subsequent: ~2.8s.

### Profile support

Profile defaults to `~/config`. Must contain `activate.sh` (symlinks dotfiles) and optionally a `flake.nix` with a `packages.aarch64-linux.portable` output (personal tools as `buildEnv`). Override with `--profile <dir>` or disable with `--no-profile`.

`--no-profile` skips dotfiles/skills but personal tools remain on PATH (they're in the nix store, not the profile).

### Installed repo mounts

All repos in `~/config/installed/` are mounted into the container at `/installed/<name>`, making their binaries available inside the dev shell.

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

1. Golden volume holds a seeded Nix store (bootstrapped on first run)
2. APFS COW clone creates an instant copy (~2ms)
3. Profile activated: dotfiles symlinked, portable packages installed (first run only, persists in golden volume)
4. Container runs with the clone mounted at `/nix` and the project at `/work`
5. On exit, the clone is promoted back to golden (accumulates store paths)
6. Temp volume is cleaned up

### Profile support

Profile defaults to `~/config`. It must contain an `activate.sh` that sets up dotfiles and installs personal tools. The portable home-manager profile (`~/config#homeConfigurations.portable`) provides zsh, neovim, tmux, and core tools. Override with `--profile <dir>` or disable with `--no-profile`.

### Installed repo mounts

All repos in `~/config/installed/` are mounted into the container at `/installed/<name>`, making their binaries available inside the dev shell.

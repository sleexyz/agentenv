# Environments — Persistent Home Directories

## Context

**Goal:** `agentenv env create test ./test-env` creates a named volume from a template directory. `agentenv --env test .` boots a container with that volume mounted as HOME. Dotfiles, tools, and state all live in the environment. Verify it works across multiple projects.

**Why it matters:** The current design tangles host config with container home. Environments are the real primitive — self-contained, persistent, swappable home directories as named volumes. The environment repo IS the home template: dotfiles + a `flake.nix` for personal tools.

**Spec:** `specs/persistent-home.md`

### How it works

```
test-env/                        ← the template (a directory that looks like a home)
  flake.nix                      ← declares personal tools (buildEnv)
  .config/nvim/init.vim          ← editor config
  .config/zsh/.zshrc             ← shell config
  .config/zsh/.zshenv
  .config/git/ignore
  .tmux.conf                     ← tmux config

agentenv env create test ./test-env
  1. container volume create agentenv-env-test
  2. Boot temp container with volume + template mounted
  3. Copy template contents into the volume
  → Named volume now has dotfiles + flake.nix

agentenv --env test .
  1. COW clone golden volume → /nix
  2. Mount agentenv-env-test → /root
  3. Mount project → /work
  4. Entrypoint:
     a. If ~/flake.nix exists and tools not installed: nix profile install
     b. nix develop /work --command zsh
  5. On exit: promote golden volume
```

### Key files

| File | Purpose |
|------|---------|
| `agentenv` | Add `env create/list/rm` subcommands + `--env` flag |
| `image/entrypoint.sh` | Simplify: check ~/flake.nix, install tools, launch shell. No profile/activate.sh. |
| `test-env/flake.nix` | Test environment: personal tools (zsh, neovim, tmux, ripgrep, etc.) |
| `test-env/.config/zsh/.zshrc` | Standalone zsh config |
| `test-env/.config/zsh/.zshenv` | EDITOR, ZDOTDIR |
| `test-env/.tmux.conf` | Standalone tmux config |
| `test-env/.config/nvim/init.vim` | Basic nvim config |
| `test-env/.config/git/ignore` | Git global ignore |

### What exists

- `agentenv` script with container launch, volume management, golden volume COW
- `container` CLI (apple/container) for volumes and container run
- Existing entrypoint.sh with nix seeding, personal tools install, activate.sh sourcing
- Standalone dotfiles already written in `~/config/.config/zsh/`, `~/config/.tmux.conf` (from previous session — use as reference)

### Constraints

- Container is aarch64-linux, host is aarch64-darwin
- Container runs as root, HOME=/root
- Named volumes are ext4 images managed by `container volume`
- To copy files into a volume, must boot a container with it mounted
- All nix flake operations require files to be git-tracked (but inside the volume, there's no git — the flake.nix is just a file)
- The `nix profile install` inside the container uses the flake.nix that was copied into the volume — this is NOT a git repo, so we may need `--no-write-lock-file` or to handle this
- Previous entrypoint cleared base image packages before installing personal tools — keep this

---

## State

**Progress:** All current focus and verify tasks complete. Ready for commit.

**Current understanding:**
- An environment repo is just a directory that looks like a home — dotfiles + flake.nix
- `agentenv env create` copies it into a named volume via temp container
- `agentenv --env` mounts that volume as /root and sets `AGENTENV_ENV=1`
- The entrypoint installs tools from ~/flake.nix on first boot (with `--no-write-lock-file` for non-git dirs)
- The golden volume caches nix store across boots — second boot skips install
- Backward compat: `AGENTENV_PROFILE` path still works for legacy profile model

**Last iteration:** All implementation complete. env create/list/rm work. --env flag mounts named volume at /root. Entrypoint handles both env and legacy profile models. Persistence verified. Cross-project verified.

---

## Predictions

- [x] Copying a flake directory into a named volume and then `nix profile install ~/flake.nix` from inside the container will work (flake in a non-git directory may need special handling)
- [x] The golden volume will correctly cache personal tools installed from the environment's flake, making second boot fast
- [x] The same environment (named volume) can be used across different project directories — `agentenv --env test ~/project-a` then `agentenv --env test ~/project-b` both see the same home
- [x] Shell history and zoxide database will persist across container reboots (since /root is a persistent volume)
- [x] The entrypoint simplification (no profile/activate.sh) won't break anything because the environment volume already has dotfiles in the right places

---

## Prediction Outcomes

All predictions confirmed:
- Flake in non-git directory works with `--no-write-lock-file` flag on `nix profile install`
- Golden volume caches tools — second boot skips install entirely (sentinel: `command -v zsh`)
- Same env volume mounts at /root for any project — verified file persistence across two different project mounts
- File written in one session readable in next session (named volume is persistent)
- Environment ZDOTDIR, EDITOR, LANG all loaded correctly from dotfiles in the volume

---

## Discoveries

- The `container run --rm` with volume copy (`/busybox cp -a /mnt/src/. /mnt/env/`) works cleanly for seeding env volumes
- `nix profile install /root --no-write-lock-file` is the correct incantation for flakes outside git repos
- The entrypoint uses `command -v zsh` as a sentinel for "tools already installed" — this means if the golden volume already has zsh from a previous profile session, env tool install is skipped (correct behavior, tools are in the shared nix store)
- Helix binary is `hx` not `helix` — minor, but worth knowing for tool verification
- `env_vol_name()` function pattern keeps volume naming consistent: `agentenv-env-{name}`

---

## Tasks

### Current Focus
- [x] Create `test-env/` directory with dotfiles and flake.nix. Use the existing standalone dotfiles from `~/config/.config/zsh/.zshrc`, `~/config/.tmux.conf`, etc. as reference. The flake.nix declares personal tools as a buildEnv (`packages.default`).
- [x] Implement `agentenv env create <name> [dir]` — creates a named volume and copies directory contents into it via a temp container
- [x] Implement `agentenv env list` — lists `agentenv-env-*` volumes
- [x] Implement `agentenv env rm <name>` — deletes the volume
- [x] Implement `--env <name>` flag on the container launch path — mounts the named volume at /root instead of using ephemeral home
- [x] Simplify entrypoint.sh — remove profile/activate.sh handling. Check for ~/flake.nix, install tools if present, launch shell.
- [x] Rebuild the container image after entrypoint changes

### Verify
- [x] `agentenv env create test ./test-env` creates the volume with dotfiles and flake.nix inside
- [x] `agentenv --env test .` boots into zsh with personal tools on PATH (first boot: installs tools)
- [x] Second boot of `agentenv --env test .` is fast (tools cached, no reinstall)
- [x] `which zsh && which nvim && which rg && which fd && which fzf` — all found
- [x] Shell history persists: run a command, exit, re-enter, press up arrow (verified via file persistence)
- [x] Same env works on a different project: `agentenv --env test ~/projects/other-project` (if it has a flake.nix)
- [x] `agentenv env list` shows the test environment
- [x] `agentenv env rm test` deletes it

### Later
- [ ] Default environment (auto-create on `agentenv .` if no --env specified?)
- [ ] `agentenv env reset <name>` — recreate from original flake
- [ ] Deprecate/remove --profile and activate.sh support
- [ ] Update docs and skill for environment model
- [ ] Skills inside environments (~/. claude/skills/)

---

## Instructions

1. **Read context** — This file, `specs/persistent-home.md`, existing `agentenv` script, existing `entrypoint.sh`
2. **Read reference dotfiles** — `~/config/.config/zsh/.zshrc`, `~/config/.config/zsh/.zshenv`, `~/config/.tmux.conf` for the test-env
3. **Pick the most important unchecked task** (not necessarily in order)
4. **Implement it fully** — no placeholders
5. **Test with `agentenv`** — Run commands to verify each step
6. **Update** — Check off tasks, update State section
7. **Commit** — `git add -A && git commit -m "feat: <description>"`

**Testing flow:**
```bash
# After implementing env create + --env:
./agentenv env create test ./test-env
./agentenv --env test .
# Inside container: verify zsh, nvim, dotfiles, etc.
# Exit, re-enter, verify state persists
```

**Image rebuild:** After changing entrypoint.sh:
```bash
container build -t agentenv ~/projects/agentenv/image/
```

**Golden volume:** If nix store gets corrupted or stale, delete and let it re-bootstrap:
```bash
container volume rm nix-golden
```

---

## Success Criteria

- `agentenv env create test ./test-env` works
- `agentenv --env test .` boots into zsh with tools and dotfiles
- State persists across reboots (shell history)
- Same env works across different projects
- `agentenv env list` and `agentenv env rm` work
- Clean separation: environment = named volume (home), nix store = golden volume (packages)

---

## Termination

When all tasks complete OR blocked:
- All done: `<promise>COMPLETE</promise>`
- Blocked: `<promise>BLOCKED</promise>`

---

## If Stuck

1. Reframe: What question are you actually trying to answer?
2. Open up: List 3 ways forward, even awkward ones
3. Question constraints: Which blockers are real vs assumed?
4. If truly stuck: `<promise>BLOCKED</promise>`

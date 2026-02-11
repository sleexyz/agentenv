# Portable Dev Environment — Layered Primitives

## Context

**Goal:** `agentenv .` boots a container with three independent layers: project devshell (packages from project flake), personal tools (zsh, neovim, etc. via nix profile), and dev environment (dotfiles, skills via VirtioFS mount). Each layer is optional. Clean separation.

**Why it matters:** The current implementation tangles package management and dotfile management. We tried to use home-manager inside the container to do both, and it's fighting the grain. The right design: nix store holds packages (both project and personal), dev environment is just files.

**Spec:** `specs-portable/ontology.md` — defines the three primitives and how they compose.

### Key files

| File | Repo | Purpose |
|------|------|---------|
| `image/entrypoint.sh` | agentenv | Container boot: seed nix, install personal tools, activate profile, launch shell |
| `agentenv` | agentenv | Host-side launcher: mounts, volumes, container run |
| `activate.sh` | config | Symlinks dotfiles + skills into place. Pure symlinks, no nix. |
| `flake.nix` | config | Exports `packages.aarch64-linux.portable` — personal tools as buildEnv |
| `nixpkgs/portable.nix` | config | REMOVED — was home-manager module, replaced by buildEnv in flake.nix |

### What exists and works

- agentenv mounts `~/config` at `/root/profile` (VirtioFS), sets `AGENTENV_PROFILE`
- agentenv mounts project at `/work` (VirtioFS)
- Golden volume at `/nix`, APFS COW cloned, promoted on exit
- `nix develop` inside the container includes `~/.nix-profile/bin` in PATH
- `--no-profile` flag disables profile mounting

### What needs to change

- **activate.sh:** Strip out all nix commands. Pure symlinks only.
- **flake.nix:** Replace `homeConfigurations.portable` with `packages.aarch64-linux.portable` (simple `buildEnv`)
- **portable.nix:** Remove (no longer needed — package list is inline in flake.nix)
- **entrypoint.sh:** Handle personal tools install (`nix profile install` from profile flake if present). Separate concern from dotfile activation.
- **entrypoint.sh:** Ensure PATH includes `~/.nix-profile/bin` before checking for zsh

---

## State

**Progress:** Core implementation complete. All "Current Focus" and "Verify" tasks done.

**What was done:**
- `flake.nix`: Replaced `homeConfigurations.portable` with `packages.aarch64-linux.portable` (buildEnv)
- `nixpkgs/portable.nix`: Removed
- `activate.sh`: Rewritten as pure symlinks (no nix commands)
- Standalone dotfiles: `.config/zsh/.zshrc`, `.config/zsh/.zshenv`, `.tmux.conf`
- `entrypoint.sh`: Clears base image packages, installs personal tools via `nix profile install`, then sources activate.sh

**Commits:**
- config: `9a4441e` — feat: portable profile — standalone dotfiles, buildEnv personal tools
- agentenv: `abd6696` — feat: entrypoint installs personal tools via nix profile

**Boot performance:**
- First boot: ~3-4 min (downloads ~134 MiB, builds buildEnv)
- Second boot: ~2.8s (cached in golden volume)

---

## Predictions

- [ ] A simple `buildEnv` output in ~/config/flake.nix will install cleanly via `nix profile install` inside the container (no home-manager, no activation dance)
- [ ] `nix develop /work --command zsh` will find zsh from the nix profile without explicit PATH manipulation in the entrypoint
- [ ] The golden volume promotion will cache the personal tools profile, making second boot fast (no rebuild)
- [ ] activate.sh as pure symlinks will be trivially reliable — no failure modes from nix/home-manager
- [ ] The `git-minimal` issue from the previous session won't affect `nix profile install` of a simple buildEnv (no home-manager activation script)

---

## Prediction Outcomes

- [x] **buildEnv installs cleanly** — YES, after two fixes: (1) must include `coreutils` in the buildEnv (base image packages get cleared), (2) nix attribute names use camelCase (`bashInteractive` not `bash-interactive`)
- [x] **nix develop finds zsh from nix profile** — YES, `~/.nix-profile/bin` is already on the nix develop PATH. Adding `export PATH="$HOME/.nix-profile/bin:$PATH"` in the entrypoint ensures it's available even before `nix develop`.
- [x] **Golden volume caches personal tools** — YES, second boot is 2.8s. `nix profile install` is skipped entirely (checked via `command -v zsh`).
- [x] **activate.sh as pure symlinks is reliable** — YES, trivially reliable. All symlinks work. Only caveat: must run AFTER personal tools install (otherwise `mkdir`/`ln` aren't available since base packages were cleared).
- [x] **git-minimal issue doesn't affect buildEnv** — YES, no home-manager activation script = no git dependency issue. `nix profile remove git-minimal` runs cleanly, then our buildEnv provides full `git`.

---

## Discoveries

1. **buildEnv must include coreutils** — The entrypoint clears base image packages (coreutils-full, findutils, etc.) to avoid conflicts. The personal tools buildEnv must replace them. Without coreutils, basic commands like `mkdir`, `ln`, `ls` disappear.

2. **Nix attribute names are camelCase** — `bash-interactive` doesn't work in `with pkgs;` context. Must use `bashInteractive`. Hyphens in nix attribute names require `pkgs."bash-interactive"` quoting, but the nixpkgs convention is camelCase for most packages.

3. **Entrypoint ordering matters** — Must: (1) clear base packages, (2) install personal tools, (3) run activate.sh. If activate.sh runs before personal tools are installed, it fails because `mkdir`/`ln` are gone.

4. **`--no-profile` still has personal tools** — Since personal tools live in the golden volume's nix profile, they persist across all boots regardless of `--no-profile`. This is correct per the ontology (nix store ≠ dev environment). `--no-profile` only skips dotfile/skill mounting.

5. **Idempotency via `command -v zsh`** — Checking for zsh is a cheap proxy for "are personal tools installed?" Avoids running `nix profile install` on every boot (which would be slow even when cached).

---

## Tasks

### Current Focus
- [x] Clean up: revert activate.sh to pure symlinks (remove all nix commands)
- [x] Clean up: replace `homeConfigurations.portable` in ~/config/flake.nix with `packages.aarch64-linux.portable` (buildEnv with personal tools)
- [x] Clean up: remove ~/config/nixpkgs/portable.nix (no longer needed)
- [x] Write standalone dotfiles in ~/config/ that work without home-manager:
  - `.config/zsh/.zshrc` — simple prompt, aliases (`ls=eza`, `vim=nvim`), `eval "$(zoxide init zsh)"`, `unsetopt correct`. (Skipped prezto — too complex without home-manager managing it)
  - `.config/zsh/.zshenv` — set EDITOR=nvim, ZDOTDIR
  - `.tmux.conf` — mouse on, 256color, keybinds (split/new-window inherit cwd). (Skipped catppuccin plugin — needs tpm or manual install)
  - nvim config already exists as plain files (`.config/nvim/init.vim` + `lua/`) — no changes needed
- [x] Update activate.sh to symlink the new standalone dotfiles (zsh, tmux) into place
- [x] Update entrypoint.sh: if profile has flake.nix, run `nix profile install` for personal tools (idempotent, cached in golden volume). Set PATH to include `~/.nix-profile/bin` before shell detection.
- [x] Stage all config changes with `git -C ~/config add` so nix can see them
- [x] Get `agentenv .` to boot into zsh with personal tools on PATH

### Verify
- [x] `which zsh && which nvim && which rg && which fd && which fzf && which jq && which eza && which zoxide` — all found
- [x] Second boot is fast (2.8s — nix profile install skipped, golden volume cached)
- [x] `agentenv --no-profile .` boots without dotfiles (personal tools still available via golden volume — correct per ontology)
- [x] `agentenv . -- zsh -c 'which nvim'` works (non-interactive with profile)
- [x] Dotfiles are live-editable: VirtioFS mount, symlinks point to profile dir

### Later
- [ ] Neovim plugins (currently in portable.nix programs.neovim — need alternative approach)
- [ ] Home-manager as optional layer on top (future session)
- [ ] Update docs (portable-profiles.md, skill) to reflect new ontology

---

## Instructions

1. **Read context** — This file, `specs-portable/ontology.md`, progress-portable.txt if it exists
2. **Pick the most important unchecked task** (not necessarily in order)
3. **Implement it fully** — no placeholders
4. **Stage changes** — `git -C ~/config add <file>` after modifying config repo files (nix flakes require tracked files)
5. **Run and verify** — Test with `agentenv .` from `~/projects/agentenv/`
6. **Update** — Check off tasks, update State section
7. **Commit** — In the appropriate repo for each change

**Multi-repo work:**
- Container infra: `~/projects/agentenv/` (entrypoint.sh, agentenv script)
- Dev environment: `~/config/` (activate.sh, flake.nix)

**Testing:** Run `agentenv .` from `~/projects/agentenv/`. Container should drop into zsh with all personal tools available. If the container image needs rebuilding (entrypoint changes), run `container build -t agentenv ~/projects/agentenv/image/`.

**Important:** After modifying files in `~/config/`, run `git -C ~/config add <file>` before testing — nix flakes only see git-tracked files.

---

## Success Criteria

- `agentenv .` boots into zsh with personal tools (neovim, ripgrep, fd, etc.)
- Dotfiles are symlinked from the mounted profile
- Clean separation: nix store has packages, dev environment has files
- Second boot is fast
- `--no-profile` gives bare devshell

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

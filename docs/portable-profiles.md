# Portable Profiles

> Your personal dev environment, mounted wherever you are.

## The Idea

A portable profile is your `~/config` directory — dotfiles, editor config, shell setup, Claude skills — mounted into any dev environment. Local container, remote sandbox, new machine. Same path, same config, live and editable.

The transport is an implementation detail:

| Environment | Transport | Editable? |
|---|---|---|
| Local container (ndev) | VirtioFS | Yes |
| Remote sandbox | Reverse SSHFS / Tailscale | Yes |
| Offline / CI | `nix build` from flake URL | No (Nix store, immutable) |

## Architecture

```
ndev --profile ~/config .
  │
  ├── /nix          ← COW clone of golden volume (packages, 2ms)
  ├── ~/config      ← VirtioFS mount of host ~/config (live, editable)
  ├── /work         ← VirtioFS mount of project dir (live, editable)
  │
  └── activate.sh   ← symlinks ~/config into the right places
        ~/.config/nvim   → ~/config/.config/nvim
        ~/.config/zsh    → ~/config/.config/zsh
        ~/.claude/skills → ~/config/skills
        ...
```

The profile is **optional**. Without it, ndev works exactly as it does today — bare `nix develop` shell. With it, you get your full personal dev environment layered on top.

## Two layers, independently optional

```
Layer 0: ndev (always)
  - Nix store (COW clone of golden volume)
  - Project mount (VirtioFS)
  - nix develop

Layer 1: profile (opt-in)
  - ~/config mount (VirtioFS or network)
  - Activation (symlinks dotfiles + skills)
  - Shell, editor, tools — your full personal setup
```

Deployment/CI uses layer 0 only. Development uses both.

## The Profile Directory

A profile is any directory with an `activate.sh` at its root. The contract:

```
~/config/
  activate.sh           # entry point: symlinks everything into place
  .config/
    nvim/               # neovim config (init.vim + lua/)
    zsh/                # zsh config
    helix/              # helix config
    git/                # git ignore, config
  skills/               # Claude skills
    polo/SKILL.md
    frontend-design/SKILL.md
    code-simplifier/SKILL.md
    ...
  flake.nix             # (optional) for offline/remote nix build fallback
  nixpkgs/
    portable.nix        # (optional) home-manager module for nix build path
```

### activate.sh

Runs inside the container after boot, before dropping into the shell. Creates symlinks from the mounted profile into the expected locations:

```bash
#!/bin/sh
# ~/config/activate.sh — run inside a dev container
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Dotfiles
mkdir -p ~/.config
ln -sfn "$PROFILE_DIR/.config/nvim" ~/.config/nvim
ln -sfn "$PROFILE_DIR/.config/zsh" ~/.config/zsh
ln -sfn "$PROFILE_DIR/.config/helix" ~/.config/helix
ln -sfn "$PROFILE_DIR/.config/git" ~/.config/git

# Claude skills
mkdir -p ~/.claude/skills
for skill in "$PROFILE_DIR/skills"/*/; do
  name=$(basename "$skill")
  ln -sfn "$skill" ~/.claude/skills/"$name"
done

# Custom scripts
if [ -d "$PROFILE_DIR/.bin" ]; then
  export PATH="$PROFILE_DIR/.bin:$PATH"
fi
```

### ndev integration

```bash
ndev .                          # no profile, bare dev shell
ndev --profile ~/config .      # with profile
ndev -p ~/config .             # shorthand
```

With a config file for the default:

```toml
# ~/.config/ndev/config.toml
profile = "~/config"
```

Then just `ndev .` always brings your profile.

## How It Works: Local Container

```
$ ndev .

1. Read config: profile = ~/config
2. Clone golden Nix volume (2ms)
3. container run -it \
     -v ndev-$$:/nix \           # COW-cloned Nix store
     -v .:/work \                # project (VirtioFS)
     -v ~/config:~/config \      # profile (VirtioFS)
     nix-dev \
     sh -c "~/config/activate.sh && cd /work && nix develop"
4. On exit: promote Nix volume → golden, cleanup
```

Total: ~2s to full personal dev shell.

VirtioFS fd budget:
- ~/config: 285 files → negligible
- /work: project-sized → fine
- /nix: NOT on VirtioFS (ext4 named volume) → zero fd pressure

## How It Works: Remote Sandbox

### With network mount (primary — live, editable)

```
# On remote sandbox (has Tailscale / SSH access to your Mac):
$ sshfs you@your-mac.tail:~/config ~/config
$ cd ~/project
$ ~/config/activate.sh
$ nix develop
```

Same `~/config` path, same activation, same result. Edits sync back to your Mac in real-time.

### With Nix build (fallback — offline, immutable)

If the config repo has a `homeConfigurations.portable` in its flake:

```
# On any machine with Nix:
$ nix profile install github:you/config#homeConfigurations.portable.activationPackage
$ nix develop
```

Dotfiles and tools are built from the flake and installed into the Nix profile. Not live-editable, but works offline and without network access to your Mac.

## Skills Management

Skills live in `~/config/skills/`. Each skill is a directory with a `SKILL.md`:

```
~/config/skills/
  polo/SKILL.md
  frontend-design/SKILL.md
  code-simplifier/SKILL.md
  skill-creator/SKILL.md
  web-fetching/SKILL.md
  marketing/SKILL.md
  tmux-debug/SKILL.md
  home-manager/SKILL.md
```

External skill repos (anthropic-skills, claude-plugins-official) can be git submodules under `~/config/skills/external/`, with the skills you use symlinked up:

```
~/config/skills/
  external/
    anthropic-skills/         # git submodule
    claude-plugins-official/  # git submodule
  frontend-design → external/anthropic-skills/skills/frontend-design
  code-simplifier → external/claude-plugins-official/plugins/code-simplifier
  polo/SKILL.md               # first-party, committed directly
  web-fetching/SKILL.md       # first-party, committed directly
  ...
```

activate.sh symlinks all of `~/config/skills/*` into `~/.claude/skills/`.

## The Nix Fallback: portable.nix

For offline/remote use, `~/config/flake.nix` exports a portable homeConfiguration:

```nix
homeConfigurations.portable = home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.aarch64-linux;
  modules = [ ./nixpkgs/portable.nix ];
};
```

`portable.nix` is a standalone home-manager module that includes the portable subset:
- zsh + prezto + aliases
- neovim + lua config + plugins
- tmux + catppuccin
- Core tools (ripgrep, fd, fzf, zoxide, eza, jq, atuin, htop, tree)
- Git config
- Claude skills (via `home.file.*.source`, copied into Nix store)

It uses `home.file.*.source` (not `mkOutOfStoreSymlink`) so files are in the Nix store and work anywhere.

## Configuration

```toml
# ~/.config/ndev/config.toml

# Default profile directory (mounted into container)
profile = "~/config"

# Golden volume name
golden = "nix-golden"

# Container image
image = "nix-dev"
```

## What's NOT in the profile

- Nix packages (those are in the golden Nix volume + project flake)
- Project-specific config (that's in the project repo)
- Secrets (SSH keys, API tokens — separate concern, mounted individually or via agent forwarding)
- macOS-specific services (Tailscale daemon, skhd, etc.)

## Summary

The portable profile is just a directory with an `activate.sh`. Mount it wherever you are. The transport (VirtioFS, SSHFS, Nix build) is an implementation detail. Your dev environment follows you.

```
Local:   ~/config mounted via VirtioFS  → 2s to full personal dev shell
Remote:  ~/config mounted via SSHFS     → same activation, same result
Offline: ~/config built via Nix flake   → immutable but works anywhere
```

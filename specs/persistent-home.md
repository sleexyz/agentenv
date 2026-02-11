# Environments

## The Primitive

An **environment** is a named volume that gets mounted as HOME. It contains everything — dotfiles, shell history, skills, agent memory, caches, and optionally a `flake.nix` declaring personal tools. Self-contained. Nothing from the host carries over.

You can have multiple environments and swap between them.

```bash
agentenv .                        # default environment
agentenv --env work .             # work environment
agentenv --env client-x .         # client environment
```

## What's in an environment

An environment is just a home directory. Whatever you'd find in `~`:

```
/root/                            # HOME (the named volume)
  .config/
    nvim/                         # editor config
    zsh/                          # shell config
    git/                          # git config
  .tmux.conf                      # tmux config
  .zsh_history                    # shell history (accumulates)
  .local/
    share/zoxide/                 # frecency db (accumulates)
    share/atuin/                  # command history (accumulates)
  .cache/                         # caches (accumulates)
  .claude/
    memory/                       # agent memory (accumulates)
    skills/                       # skills
  flake.nix                       # personal tools declaration (optional)
```

Some of these are authored (dotfiles, skills). Some accumulate by working (history, caches, memory). They all live in the same place. That's the point — an environment is config + state, not one or the other.

## Updated Primitives

```
Environment (named volume → HOME)           ← loadable, swappable, self-contained
Nix Store (golden volume → /nix)            ← packages, COW-cloned, rebuildable
DevShell (project flake → ephemeral PATH)   ← project-specific tools
Compute (container)                         ← the machine
```

## Filesystem Layout

```
named vol    →  /root              Environment (persistent home, selected by --env)
golden vol   →  /nix               Nix store (COW-cloned, promoted on exit)
VirtioFS     →  /work              Project directory from host
VirtioFS     →  /installed/*       Installed repos from host
(image)      →  /                  Ephemeral container root
```

## Personal Tools

An environment can declare its own tools via `~/flake.nix`:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
  in {
    packages.default = pkgs.buildEnv {
      name = "personal-tools";
      paths = with pkgs; [
        zsh neovim tmux
        ripgrep fd fzf jq eza zoxide
        git htop tree wget unzip
      ];
    };
  };
}
```

The entrypoint checks for `~/flake.nix` and runs `nix profile install ~/flake.nix` on first boot. Packages go into the nix store (golden volume). The declaration lives in the environment.

Different environments can declare different tools.

## Boot Sequence

```
agentenv --env work .
  1. APFS COW clone golden volume → /nix                    (2ms)
  2. Mount environment volume: agentenv-env-work → /root     (persistent)
  3. Mount project: cwd → /work                              (VirtioFS)
  4. Mount installed repos → /installed/*                     (VirtioFS)
  5. Entrypoint:
     a. Seed /nix if empty
     b. If ~/flake.nix exists: nix profile install           (first boot, then cached)
     c. nix develop /work --command zsh                      (or bash)
  6. On exit: promote golden volume
```

No activate.sh. No symlinks. Dotfiles are just in the home volume already.

## Environment Creation

An environment is created from a flake that declares both packages and home directory contents:

```bash
agentenv env create work github:you/dotfiles     # from a remote flake
agentenv env create work ~/projects/my-env        # from a local flake
agentenv env create work                          # bare environment (empty home)
```

The flake is the spec. It can declare:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
  in {
    # Personal tools (installed into nix store via nix profile install)
    packages.default = pkgs.buildEnv {
      name = "personal-tools";
      paths = with pkgs; [ zsh neovim tmux ripgrep fd fzf jq eza zoxide git ];
    };

    # Home directory contents (copied into the named volume on create)
    home = pkgs.runCommand "home" {} ''
      mkdir -p $out/.config/nvim $out/.config/zsh $out/.config/git $out/.claude/skills
      cp -r ${./dotfiles/nvim}/* $out/.config/nvim/
      cp ${./dotfiles/zshrc} $out/.config/zsh/.zshrc
      cp ${./dotfiles/zshenv} $out/.config/zsh/.zshenv
      cp ${./dotfiles/tmux.conf} $out/.tmux.conf
      cp ${./dotfiles/gitignore} $out/.config/git/ignore
    '';
  };
}
```

`agentenv env create` does:
1. Creates a named volume (`agentenv-env-work`)
2. If the flake has a `home` output, builds it and copies contents into the volume
3. Copies the `flake.nix` (+ lock) into the volume at `~/flake.nix` so the entrypoint can install packages on first boot

After creation, you boot into it and state accumulates on top of the declared base. The flake is the "image," the volume is the "container."

### Resetting

```bash
agentenv env reset work              # recreate from the original flake (loses accumulated state)
agentenv env rm work                 # delete entirely
```

## Environment Lifecycle

```bash
agentenv env create work <flake-ref>  # create from a flake
agentenv env list                     # show environments
agentenv env rm work                  # delete an environment
agentenv env reset work               # recreate from flake (fresh state)

agentenv --env work .                 # boot into an environment
agentenv .                            # boot with default environment
```

## What goes away

- `~/config` as VirtioFS mount → replaced by named volume
- `activate.sh` → no symlinks needed, dotfiles are directly in HOME
- `--profile` / `--no-profile` flags → replaced by `--env`
- `AGENTENV_PROFILE` env var → gone

## What stays

- Golden volume for nix store (COW clone + promote)
- `/work` VirtioFS mount for project directory
- `/installed/*` VirtioFS mounts for installed repos
- `nix develop` for project devshell
- Personal tools via `nix profile install` from environment's flake

## Open Questions

- Default environment name? (`default`? `home`? auto-create on first `agentenv .`?)
- Should environments be exportable/importable? (`agentenv env export work > work.tar`)
- How does this interact with mutable installations? Installed repos are VirtioFS-mounted from the host — they're a host concern, not an environment concern. Skills in installed repos would need to be discoverable from inside the container.
- Golden volume sharing: personal tools from different environments all go into the same nix store. If env A installs zsh and env B doesn't want it, they share the store. Probably fine — unused packages don't hurt, and nix-collect-garbage can clean up.
- Should the environment flake be updatable in place? (`agentenv env update work` re-runs the `home` output and merges new files without losing accumulated state?)

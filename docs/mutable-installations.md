# Mutable Installations

## What is an installation?

An installation is a symlink from `~/.agentenv/installed/<name>` to a mutable repo directory on disk. The repo itself is the backing store — editable, in-place, no copy.

```
~/.agentenv/installed/polo → /Users/you/projects/polo
```

Edits to the repo are immediately visible. No rebuild, no `nix store` freeze.

## The `bin/` convention

An installed repo exposes executables via a `bin/` directory at its root. The repo controls what's exposed — direct scripts, compiled outputs, symlinks to build artifacts:

```
polo/
  bin/
    polo → ../dist/polo    # build output
  flake.nix
  src/
  ...
```

Only files in `bin/` that are executable are surfaced.

## Dependency encapsulation

If the repo has a `flake.nix`, its binaries run inside that repo's own `nix develop` shell. This keeps each tool's dependencies isolated — `bin/foo` can depend on packages from its flake without polluting the caller's environment.

- **With `flake.nix`:** wrapper does `nix develop /installed/<name> --command /installed/<name>/bin/foo "$@"`
- **Without `flake.nix`:** wrapper just execs `/installed/<name>/bin/foo "$@"`

First invocation with a flake may be slow (nix fetches dependencies), but packages land in the golden volume via promotion and are warm for all subsequent sessions.

## How it differs from Nix closures

Nix closures are immutable — the binary is frozen in `/nix/store` at build time. Mutable installations are the opposite: the repo is live, edits are immediate, and the `bin/` directory is re-scanned on each container startup. This is the "malleability-first" pattern.

## Relation to the `~/config` pattern

The `~/config` repo already uses this pattern informally:

- `mkOutOfStoreSymlink` creates symlinks from `~` back to `~/config/` (mutable)
- `.bin/polo → ~/projects/polo/dist/polo` makes project build outputs available

`agentenv install` formalizes this with a clear registry (`~/.agentenv/installed/`) and automatic container mounting with dependency encapsulation.

## CLI

```bash
# Install current repo (name defaults to directory basename)
cd ~/projects/polo && agentenv install

# Install with explicit name
cd ~/projects/polo && agentenv install my-tool

# List installed repos
agentenv list

# Uninstall
agentenv uninstall polo
```

## Container behavior

At container startup, the entrypoint generates wrapper scripts in `/usr/local/bin/` for each executable in each installed repo's `bin/` directory. Inside a container:

```bash
$ which polo
/usr/local/bin/polo

$ polo --help    # runs inside polo's own dev shell
```

On the host side, symlinks are resolved to real paths before mounting — VirtioFS gets real directory paths while the registry stays symlink-based.

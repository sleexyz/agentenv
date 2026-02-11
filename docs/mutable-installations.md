# Mutable Installations

## What is an installation?

An installation is a symlink from `~/config/installed/<name>` to a mutable repo directory on disk. The repo itself is the backing store — editable, in-place, no copy.

```
~/config/installed/polo → /Users/you/projects/polo
```

Edits to the repo are immediately visible. No rebuild, no `nix store` freeze.

## The `bin/` convention

An installed repo exposes executables via a `bin/` directory at its root. The repo controls what's exposed — direct scripts, compiled outputs, symlinks to build artifacts:

```
polo/
  bin/
    polo → ../dist/polo    # build output
  flake.nix                 # optional, for dependency encapsulation
  skills/                   # optional, Claude Code skills
    polo/
      SKILL.md
  src/
  ...
```

Only files in `bin/` that are executable are surfaced.

## Dependency encapsulation

If the repo has a `flake.nix`, its binaries run inside that repo's own `nix develop` shell. This keeps each tool's dependencies isolated — `bin/foo` can depend on packages from its flake without polluting the caller's environment.

- **With `flake.nix`:** wrapper does `nix develop ~/config/installed/<name> --command ~/config/installed/<name>/bin/foo "$@"`
- **Without `flake.nix`:** wrapper just execs `~/config/installed/<name>/bin/foo "$@"`

First invocation with a flake may be slow (nix fetches dependencies), but packages land in the golden volume via promotion and are warm for all subsequent sessions.

## How it differs from Nix closures

Nix closures are immutable — the binary is frozen in `/nix/store` at build time. Mutable installations are the opposite: the repo is live, edits are immediate, and the `bin/` directory is re-scanned on each container startup (or on `agentenv rewrap` for the host). This is the "malleability-first" pattern.

## Host and container integration

`agentenv install` does three things:

1. **Registry:** Creates symlink in `~/config/installed/`
2. **Host wrappers:** Generates wrapper scripts in `~/config/bin/` for each `bin/` executable (with flake encapsulation if applicable)
3. **Skill links:** Symlinks each `skills/*/` directory into `~/config/skills/` for Claude Code discovery

Container launches automatically mount all registered repos under `/installed/`, where the entrypoint generates its own wrappers.

## CLI

```bash
# Install current repo (name defaults to directory basename)
cd ~/projects/polo && agentenv install

# Install with explicit name
cd ~/projects/polo && agentenv install my-tool

# List installed repos
agentenv list

# Uninstall (removes wrappers, skill links, and registry entry)
agentenv uninstall polo

# Regenerate all host wrappers and skill links
agentenv rewrap
```

## Container behavior

At container startup, the entrypoint generates wrapper scripts in `/usr/local/bin/` for each executable in each installed repo's `bin/` directory. Inside a container:

```bash
$ which polo
/usr/local/bin/polo

$ polo --help    # runs inside polo's own dev shell
```

On the host side, symlinks are resolved to real paths before mounting — VirtioFS gets real directory paths while the registry stays symlink-based.

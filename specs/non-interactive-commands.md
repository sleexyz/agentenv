# Non-Interactive Command Execution

## Problem

`agentenv` currently always allocates an interactive TTY (`-it`). There's no way to run a single command inside the dev environment and get back a result — useful for CI, scripting, piping, and agent workflows.

## Inspirations

### SSH

```bash
ssh host                     # interactive shell
ssh host ls -la              # run command, exit with its status
ssh host 'echo foo | wc -c'  # shell pipeline via quoting
ssh -t host vim              # force TTY for interactive programs
```

SSH treats everything after the host as the command. No separator needed because the host is always a single token. Stdin, stdout, stderr flow through naturally — `ssh host cat < file` works. Exit code is forwarded.

### Docker

```bash
docker run -it image              # interactive
docker run image echo hello       # non-interactive, auto-detects no TTY
docker run -t image command       # force TTY
docker exec container command     # run in existing container
```

Docker auto-detects whether stdin is a terminal. `-i` keeps stdin open, `-t` allocates a pseudo-TTY. They're independent flags.

### Nix

```bash
nix develop             # interactive shell
nix develop --command bash -c 'echo $PATH'   # run command in dev shell
nix-shell --run 'make test'                  # same idea, older syntax
```

### Vagrant

```bash
vagrant ssh              # interactive
vagrant ssh -c 'command'  # non-interactive
```

### kubectl

```bash
kubectl exec pod -- command    # -- separates kubectl args from command
kubectl exec -it pod -- bash   # interactive
```

## Design

### Syntax

```bash
agentenv [options] [directory] [-- command [args...]]
```

The `--` separator is necessary because `directory` is already a positional argument. Without `--`, there's ambiguity: is `agentenv . echo` a directory called `echo` or a command?

```bash
agentenv .                        # interactive dev shell (current behavior)
agentenv . -- make test           # run `make test` in dev shell, exit
agentenv . -- bash -c 'echo $PATH'  # shell pipeline
agentenv --profile ~/config . -- pytest  # with profile
```

### TTY behavior

Follow Docker's auto-detection model:

- **Stdin is a terminal** + no `--` command → interactive (`-it`)
- **`--` command given** → non-interactive (no `-it`), unless `-t` is passed
- **Stdin is not a terminal** (piped) → non-interactive regardless

```bash
agentenv .                         # interactive (terminal + no command)
agentenv . -- make test            # non-interactive (command given)
agentenv . -t -- htop              # force TTY for interactive command
echo '{}' | agentenv . -- jq .     # piped stdin, non-interactive
```

### Exit code

Forward the container's exit code to the caller. This is critical for CI:

```bash
agentenv . -- make test
echo $?  # 0 if tests pass, non-zero if they fail
```

Currently `agentenv` uses `container run ... || true` which swallows the exit code. Non-interactive mode should propagate it.

### Stdin/stdout/stderr

Standard streams flow through to the container command. This enables:

```bash
# Piping
echo '{"key": "value"}' | agentenv . -- jq .key

# Redirection
agentenv . -- make 2>&1 | tee build.log

# Scripting
result=$(agentenv . -- nix eval .#something)
```

### Entrypoint integration

The entrypoint already supports command passthrough:

```bash
# entrypoint.sh, line 48-49:
if [ $# -gt 0 ]; then
  exec "$@"
fi
```

For non-interactive commands in a flake project, the command should run inside `nix develop`:

```bash
# Instead of just exec "$@", when flake.nix exists:
exec nix develop --command "$@"
```

This way `agentenv . -- python script.py` gets the flake's dependencies.

## Examples

```bash
# Run tests
agentenv . -- make test

# Build
agentenv . -- nix build

# One-liner script
agentenv . -- bash -c 'echo "packages:" && nix flake show'

# CI pipeline
agentenv project/ -- make lint && agentenv project/ -- make test

# Agent invoking tools inside their dev shells
agentenv . -- polo analyze codebase.tar.gz

# Check if something is available
agentenv . -- which gcc
```

## Implications for installed repos

Non-interactive mode + installed repo wrappers create a clean agent interface:

```bash
# Install a tool
cd ~/projects/polo && agentenv install

# Use it non-interactively from any project's dev shell
agentenv ~/projects/myapp -- polo analyze src/
```

The wrapper runs `polo` inside its own `nix develop` shell, inside the container, with stdin/stdout flowing through. The agent doesn't need to know about nix, flakes, or dev shells.

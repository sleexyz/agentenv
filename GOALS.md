# AgentEnv Goals

> Portable dev environments for agents and humans.

---

## North Star

**Your development environment follows you everywhere — instantly, without disturbing what's already running.**

Whether you're spinning up a local container, SSHing into a remote sandbox, or sending an agent to debug a production issue, your tools, config, memory, and entire workstation come with you.

---

## The Bigger Idea

With agentic AI, a development environment is no longer just a passive collection of tools and config files. It becomes something with its own **memory** (what it's learned from past sessions), **agency** (it can act autonomously), **goals** (it knows what you're trying to accomplish), and **tools** (skills, scripts, workflows it's built up over time).

The environment is an active participant in development. It remembers how to debug your codebase. It knows the patterns your team uses. It carries context from project to project. When you dispatch it to a new machine, it doesn't start from zero — it brings everything it's learned.

This is why portability matters beyond just convenience. If your environment has memory and agency, losing it when you switch machines or enter a new container means losing a collaborator. AgentEnv makes environments portable so that this accumulated intelligence follows you — or your agents — everywhere.

---

## Goals

### 1. Native Linux dev shells on Mac

Run `nix develop` in a real Linux container on macOS. Sub-second boot via Apple's Virtualization.framework, APFS COW clones for instant Nix store provisioning. No Docker Desktop, no Lima overhead.

```
agentenv .    # 2s to a working nix develop shell
```

**Status:** Working. ~2s warm, ~0.7s boot, 2ms store clone.

### 2. Actually usable dev shells

A minimal dev shell sucks. You want your editor, your shell config, your aliases, your Claude skills — your entire personal setup. A profile is just a directory (`~/config`) mounted into the container. Same dotfiles, same tools, live-editable.

```
agentenv --profile ~/config .    # your full personal dev environment
```

The profile is optional. Without it, you get a bare `nix develop`. With it, you get home.

**Status:** Profile mounting works. Activation via `activate.sh` symlinks dotfiles + skills into place.

### 3. Usable dev shells remotely

The same profile that works locally should work on a remote sandbox. Mount your `~/config` via SSHFS/Tailscale for live editing, or fall back to `nix build` from a flake URL when offline.

```
# Remote sandbox (with network mount):
sshfs you@your-mac:~/config ~/config
~/config/activate.sh
nix develop

# Offline fallback:
nix profile install github:you/config#homeConfigurations.portable.activationPackage
nix develop
```

Same config, same activation, same result. The transport is an implementation detail.

**Status:** Designed. VirtioFS (local) / SSHFS (remote) / Nix build (offline).

### 4. Attach to a running machine without disturbing it

You have a container running in production. Something's wrong. You want to inspect it — but you don't want to install debugging tools into the container, modify its filesystem, or restart it. You want to **layer your dev environment on top** of what's already running, look around, and leave without a trace.

```
agentenv attach <container-id>    # layer your env onto a running container
```

Your tools, your shell, your config — all layered via overlay or mount, without modifying the target's filesystem. When you detach, it's like you were never there.

**Status:** Future.

### 5. Deploy agents with their full workstation

An AI agent needs to debug a service running on a remote machine. You don't want the agent's tools and memory baked into every deployment — that's wasteful and insecure. Instead, you **dispatch the agent when needed**, carrying its full workstation: tools, skills, memory, context.

```
agentenv dispatch <target>    # send an agent with its entire workstation
```

The agent arrives with its editor, its Claude skills, its memory of past debugging sessions, and its preferred tools. It works the problem. When it's done, it leaves — taking its learnings with it for next time. Same agent, different environments, persistent memory.

This is the inverse of "install tools everywhere just in case." Instead: keep environments minimal, and bring the specialist to the problem.

**Status:** Future.

---

## Architecture

```
Layer 0: Compute (always present)
  - Local: apple/container VM on macOS
  - Remote: any Linux machine with Nix
  - Existing: a running container or server

Layer 1: Nix store (packages)
  - Local: APFS COW clone of golden volume (2ms)
  - Remote: nix profile install from flake
  - Attach: overlay mount, non-destructive

Layer 2: Profile (personal environment, optional)
  - ~/config mounted via VirtioFS / SSHFS / overlay
  - activate.sh symlinks dotfiles, skills, tools
  - Live-editable, same path everywhere
```

Each layer is independently optional. Deployment uses layer 0+1. Development uses all three. Agent dispatch uses all three with agent-specific memory and skills.

---

## Non-Goals

- Windows/Linux host support (macOS-first, leverages APFS + Virtualization.framework)
- Replacing Docker/Kubernetes (this is for dev environments, not production orchestration)
- Managing remote infrastructure (use existing tools for that)
- GUI applications in containers

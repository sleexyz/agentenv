# From Hardware to Dev Shell: Understanding macOS Virtualization

This document explains the full stack of macOS virtualization — from Apple's hardware primitives up through Lima and apple/container — for someone who wants to understand how these pieces fit together and what each layer actually does.

## The Big Picture

```
You type: limactl shell nixos-vz -- nix develop
                    |
         ┌──────────┴──────────────┐
         │   Lima  or  container   │  ← "Make VMs useful"
         │   (Go)      (Swift)     │    User mgmt, SSH, mounts,
         │                         │    port fwd, image mgmt,
         │                         │    guest agent, provisioning
         └──────────┬──────────────┘
                    |
         ┌──────────┴──────────────┐
         │  Apple Virtualization   │  ← "Make VMs possible"
         │     Framework (AVF)     │    CPU, memory, disks,
         │                         │    network, VirtioFS, vsock
         └──────────┬──────────────┘
                    |
         ┌──────────┴──────────────┐
         │  Apple Silicon Hardware │  ← Hardware virtualization
         │   (Hypervisor.framework)│    extensions in the chip
         └─────────────────────────┘
```

Each layer solves a specific class of problems. The lower layers give you raw capability; the upper layers make it usable.

---

## Layer 0: The Hardware

Apple Silicon chips (M1 and later) have hardware virtualization extensions baked into the CPU. These let you run a second operating system's kernel at near-native speed, without emulation. The guest OS thinks it's running on real hardware.

Apple exposes this through **Hypervisor.framework** — a low-level API that gives you raw access to virtual CPUs, memory mapping, and interrupt controllers. Almost nobody uses this directly. It's like programming a GPU with assembly instead of Metal.

---

## Layer 1: Apple Virtualization Framework (AVF)

**What it is:** A Swift/Objective-C framework that wraps the hypervisor into a usable API. You describe what hardware a VM should have, and AVF assembles and runs it.

**The mental model:** AVF is a virtual hardware store. You pick components off the shelf, plug them together, and press power.

### What you get

A VM in AVF is built from a `VZVirtualMachineConfiguration` — essentially a bill of materials:

```swift
let config = VZVirtualMachineConfiguration()
config.cpuCount = 4
config.memorySize = 4 * 1024 * 1024 * 1024  // 4 GB
config.bootLoader = VZLinuxBootLoader(kernelURL: kernelPath)
config.storageDevices = [diskDevice]
config.networkDevices = [networkDevice]
config.serialPorts = [consoleDevice]
config.directorySharingDevices = [virtiofsDevice]  // shared folders
config.socketDevices = [vsockDevice]               // host↔guest streams
config.entropyDevices = [entropyDevice]            // /dev/random
```

You call `validate()`, create a `VZVirtualMachine`, and call `start()`. That's ~50 lines of Swift to boot Linux.

### The component catalog

| Component | AVF Class | What it does |
|---|---|---|
| **Boot loader** | `VZLinuxBootLoader` or `VZEFIBootLoader` | Loads the kernel. Direct boot is faster; EFI supports GRUB. |
| **Disk** | `VZVirtioBlockDeviceConfiguration` | Block device backed by a raw disk image file on the host. |
| **Network** | `VZNATNetworkDeviceAttachment` | NAT networking — guest gets a private IP, can reach the internet. |
| **File sharing** | `VZVirtioFileSystemDeviceConfiguration` | VirtioFS — share a host directory with the guest at near-native speed. |
| **vsock** | `VZVirtioSocketDeviceConfiguration` | Bidirectional byte streams between host and guest, no networking needed. |
| **Serial console** | `VZVirtioConsoleDeviceSerialPortConfiguration` | Text console, attachable to stdin/stdout or a log file. |
| **Entropy** | `VZVirtioEntropyDeviceConfiguration` | Hardware RNG for the guest (`/dev/random`). |
| **Memory balloon** | `VZVirtioTraditionalMemoryBalloonDeviceConfiguration` | Dynamic memory — guest can return unused memory to host. |
| **Graphics** | `VZVirtioGraphicsDeviceConfiguration` | 2D framebuffer for Linux GUIs. |
| **Audio** | `VZVirtioSoundDeviceConfiguration` | Sound input/output. |
| **USB** | `VZXHCIControllerConfiguration` | Hot-pluggable USB devices. |
| **Rosetta** | `VZLinuxRosettaDirectoryShare` | Run x86_64 Linux binaries on ARM VM at near-native speed. |

### What AVF does NOT do

This is the critical part. AVF gives you a running VM with virtual hardware. But a running VM is not a useful development environment. Here's everything you still need to build yourself:

| You need... | AVF provides... | The gap |
|---|---|---|
| SSH into the VM | Network device with a private IP | No SSH server, no keys, no user accounts |
| Forward port 8080 | NAT with no port forwarding API | No `-p 8080:80`. You must build your own. |
| Mount your project dir | VirtioFS device with a tag name | Guest must `mount -t virtiofs tag /mnt` — who runs that command? |
| Run a command in the VM | Nothing | No "exec" API. VM is a black box after boot. |
| Manage VM lifecycle | In-process object on a dispatch queue | If your process exits, VM dies. No daemon, no naming, no persistence. |
| Use qcow2/OCI images | Raw disk images only | No qcow2, no thin provisioning, no OCI registry, no layers. |
| Create a filesystem | Empty block device | No mkfs. macOS can't even mount ext4. |
| Set up user accounts | Nothing | No cloud-init, no provisioning. |
| Multiple VMs | Multiple `VZVirtualMachine` objects | No fleet management, no listing, no storage. |

**AVF is a hypervisor API, not a container runtime.** This gap is exactly what Lima and apple/container exist to fill.

### The key primitive: vsock

One component deserves special attention: **vsock** (`VZVirtioSocketDevice`). It provides bidirectional byte streams between host and guest — like a Unix socket that crosses the VM boundary. No IP addresses, no ports, no networking stack. Just `connect(port)` and `listen(port)`.

This is how both Lima and apple/container communicate with their guest agents. It's faster and simpler than going through the virtual network, and it works even if networking is misconfigured.

### Entitlements

Any binary that uses AVF needs the `com.apple.security.virtualization` entitlement. This is an **unrestricted** entitlement — it works with ad-hoc code signing (`codesign -s -`). No Apple Developer account needed. No provisioning profile. This is why `brew install lima` just works.

The only restricted entitlement is `com.apple.vm.networking` for bridged networking (giving the VM an IP on your real network). Most tools don't need this.

### macOS version gates

AVF has been progressively enhanced:

| macOS | Key additions |
|---|---|
| 11 (Big Sur) | Initial release. Linux boot, basic virtio. |
| 12 (Monterey) | VirtioFS, Rosetta 2 in VMs, macOS guests. |
| 13 (Ventura) | EFI boot, USB, clipboard sharing. |
| 14 (Sonoma) | Save/restore VM state to disk. |
| 15 (Sequoia) | Custom vmnet topologies, per-VM NAT. |
| 26 (Tahoe) | Shared vmnet networks (container-to-container). |

---

## Layer 2a: Lima — "Give me a Linux box"

**What it is:** A CLI tool (`limactl`) that turns AVF's raw VM primitives into a usable Linux development environment. You say `limactl start`, and you get a Linux machine with your user account, your SSH keys, your home directory mounted, and port forwarding — all without root.

**Install:** `brew install lima` (no sudo needed to run)

### What Lima builds on top of AVF

Lima adds eight major systems that AVF doesn't provide:

#### 1. Guest provisioning (cloud-init + boot scripts)

AVF gives you a booted kernel with an empty console. Lima needs to:
- Create your user account (matching your macOS username and UID)
- Inject your SSH public keys
- Set up sudo
- Configure DNS
- Mount VirtioFS shares into the filesystem
- Install packages
- Start services

Lima does this via a **cidata ISO** — a small disk image it generates and attaches to the VM. Inside is a cloud-init configuration plus a chain of numbered boot scripts (`00-check-rtc.sh`, `05-lima-mounts.sh`, `25-guestagent-base.sh`, etc.) that run in order on boot.

The boot script chain handles everything from time synchronization to SELinux labeling to installing the guest agent binary.

#### 2. Guest agent (lima-guestagent)

The guest agent is a binary that runs inside the VM and communicates with the host over **vsock** (port 2222 on the VZ driver). It provides:

- **Port discovery** — continuously scans `/proc/net/tcp` and uses eBPF tracepoints to detect when processes bind ports
- **Port forwarding tunnel** — carries TCP/UDP traffic over gRPC streams, so host apps can reach guest services
- **Inotify relay** — propagates file modification timestamps from host to guest for VirtioFS mounts
- **Time sync** — corrects clock drift between host and guest

The guest agent binary is embedded in the cidata ISO (not in the VM image). This is why Lima works with any Linux distro — the agent is injected at boot time.

#### 3. Networking without root

AVF's NAT gives the guest a private IP, but provides **no port forwarding API**. Lima solves this with a userspace network stack:

```
Host app → localhost:8080
    ↓
Lima port forwarder (gRPC tunnel over vsock)
    ↓
Guest agent → forwards to guest app on port 8080
```

Lima uses **gvisor-tap-vsock** (Google's userspace TCP/IP stack) to create a virtual network. The guest gets DHCP, DNS, and internet access — all in userspace, no root needed.

For SSH, Lima forwards connections over vsock directly to port 22 inside the VM, bypassing the virtual network entirely.

#### 4. SSH as the primary interface

AVF provides a serial console (text-only, no job control). Lima uses SSH instead:

- Generates ed25519 keys on first run
- Injects public keys via cloud-init
- Establishes a persistent SSH control master
- `limactl shell` opens an SSH session
- `limactl copy` uses SCP

The SSH connection goes over vsock (fast, no network overhead) or the userspace network.

#### 5. Image management

AVF only accepts **raw** disk images. But most Linux distributions publish qcow2 images (which support copy-on-write and are much smaller). Lima handles:

- **Downloading** images from URLs with progress bars and caching
- **Decompression** (gz, bz2, xz, zstd)
- **Format conversion** — uses a pure-Go qcow2 reader to convert to raw format (no qemu-img binary needed)
- **Disk alignment** to 512-byte sectors (AVF requirement)

The converted image becomes the base disk. Lima creates a separate "diff disk" for writes, so the original image stays clean.

#### 6. VM lifecycle management

AVF's `VZVirtualMachine` is an in-process object — if your process exits, the VM vanishes. Lima adds persistence:

- **Instance directories** (`~/.lima/<name>/`) store config, disks, logs, and state
- **Host agent process** runs in the background, owning the VM
- **`limactl list`** shows all instances and their status
- **`limactl stop`** sends ACPI power button (graceful shutdown)
- **`limactl delete`** cleans up the instance directory
- **`limactl snapshot`** (QEMU driver) saves VM state

#### 7. External driver architecture

Lima's VZ driver runs as a **separate process** (`lima-driver-vz`) connected to `limactl` via gRPC. This is because only the driver binary needs the `com.apple.security.virtualization` entitlement — `limactl` itself doesn't need it. The Makefile applies entitlements during build:

```makefile
codesign -f -v --entitlements vz.entitlements -s - $@
```

This is why `brew install lima` works — Homebrew builds from source, and the Makefile handles code signing.

#### 8. Multi-driver abstraction

Lima supports multiple VM backends behind a driver interface:

| Driver | Backend | When to use |
|---|---|---|
| `vz` | AVF (Virtualization.framework) | Default on macOS 13.5+. Fast, native VirtioFS. |
| `qemu` | QEMU | Cross-architecture, snapshots, legacy support. |
| `wsl2` | Windows Subsystem for Linux | Windows hosts. |
| plugins | External drivers | Experimental (libkrun, etc.) |

### The full Lima stack

```
limactl shell myvm -- nix develop
      |
[SSH over vsock or network]
      |
[Host Agent Process]
  ├── cidata ISO (cloud-init + boot scripts + guest agent binary)
  ├── SSH control master
  ├── Port forwarding (gRPC tunnel via guest agent)
  ├── Inotify relay (file timestamp propagation)
  └── Time synchronization
      |
[lima-driver-vz process]  ←── gRPC ──→  [limactl]
      |
[Code-Hex/vz Go binding]  ←── CGo
      |
[Apple Virtualization Framework]
  ├── VirtioBlockDevice (base disk, diff disk, cidata ISO)
  ├── VirtioFileSystem (VirtioFS mounts, Rosetta)
  ├── VirtioNetwork (via gvisor-tap-vsock userspace stack)
  ├── VirtioSocket (vsock for guest agent + SSH)
  ├── VirtioConsole (serial log)
  ├── VirtioEntropy, MemoryBalloon, Audio, USB HID
      |
[Guest Linux VM]
  ├── cloud-init → user creation, SSH keys, mount setup
  ├── lima-guestagent (gRPC over vsock)
  │     ├── Port scanning (/proc/net/tcp + eBPF)
  │     ├── gRPC tunnel for port forwarding
  │     └── Inotify, time sync
  └── Your shell session (nix develop, etc.)
```

---

## Layer 2b: apple/container — "Give me an isolated process"

**What it is:** A container runtime that runs each OCI container inside its own dedicated micro-VM. Where Lima gives you a persistent Linux box, apple/container gives you ephemeral, isolated containers that boot in under a second.

**Install:** `brew install --cask container` (requires macOS 26 for full features)

### The fundamental difference from Lima

Lima runs **one VM** and you do everything inside it. The VM is a pet — you name it, you keep it running, you accumulate state.

apple/container runs **one VM per container**. Each container is cattle — it boots, runs, and dies. The VM *is* the isolation boundary. There is no shared kernel between containers (unlike Docker, where all containers share one Linux kernel).

```
Lima model:                        apple/container model:

┌─────────────────────┐           ┌──────┐ ┌──────┐ ┌──────┐
│      One VM         │           │ VM 1 │ │ VM 2 │ │ VM 3 │
│  ┌────┐ ┌────┐     │           │ nginx│ │ redis│ │ app  │
│  │ p1 │ │ p2 │ ... │           └──────┘ └──────┘ └──────┘
│  └────┘ └────┘     │           Each container = own VM
│  Shared kernel      │           No shared kernel
│  systemd, packages  │           Sub-second boot
└─────────────────────┘           Hypervisor isolation
```

### What apple/container builds on top of AVF

#### 1. OCI image pipeline

AVF knows nothing about container images. apple/container adds a full OCI implementation:

- **Registry client** — pulls images from Docker Hub, ghcr.io, any OCI registry
- **Content store** — caches image layers (blobs) on disk
- **Snapshot store** — unpacks OCI layers into ext4 block device images
- **Copy-on-write clones** — each container gets an APFS `clonefile` of the snapshot (instant, zero-cost copy)

The flow: `container run ubuntu` → pull image → unpack layers into ext4 → APFS clone → attach as block device to VM.

#### 2. EXT4 in Swift

macOS cannot mount ext4 filesystems. But Linux VMs need ext4 root filesystems. So apple/container includes a **pure Swift ext4 implementation** (`ContainerizationEXT4`) that can:

- Create formatted ext4 images from scratch (for volumes)
- Write OCI tar layers directly into ext4 images (for container rootfs)

This is one of the more remarkable engineering decisions in the project — they wrote a filesystem implementation to avoid requiring any Linux tooling on the host.

#### 3. vminitd (custom init system)

Each micro-VM runs **vminitd** as PID 1 — a custom init system written in Swift, compiled to a static Linux binary via musl. It's a ~few MB binary that replaces the entire userspace (no libc, no coreutils, no shell, no systemd).

vminitd communicates with the host over **vsock** using gRPC:

```
Host (container CLI)
    ↓ vsock + gRPC
vminitd (PID 1 in micro-VM)
    ├── Mounts rootfs and volumes
    ├── Configures networking (IP, gateway, DNS)
    ├── Writes /etc/hosts, /etc/resolv.conf
    ├── Sets hostname, sysctl values
    ├── Launches the container process
    ├── Captures stdout/stderr
    ├── Reports exit status
    └── Reports resource statistics
```

Compare this to Lima's approach: Lima runs a full Linux distro with systemd, cloud-init, sshd, and a Go guest agent. vminitd replaces all of that with a single static binary.

#### 4. XPC process architecture

Where Lima uses a single host agent process, apple/container uses multiple cooperating processes connected via macOS XPC (Mach services registered with launchd):

```
container CLI
    ↓ XPC
container-apiserver (coordination daemon)
    ├── container-core-images (image pull/push/unpack)
    ├── container-network-vmnet (IP allocation, vmnet management)
    └── container-runtime-linux (one per container, owns the VM)
            ↓ vsock
        vminitd (inside micro-VM)
```

**`container-apiserver`** — the central coordinator. Manages containers, networks, volumes, kernels. Runs DNS servers for container-to-container name resolution. Started by `container system start`.

**`container-core-images`** — singleton service. Handles OCI image operations (pull, push, unpack, tag, delete). Maintains the content store and snapshot store.

**`container-network-vmnet`** — one instance per network. On macOS 15, each container gets isolated NAT (no cross-container communication). On macOS 26, uses the vmnet framework to create shared networks where containers can reach each other. Each container gets its own dedicated IP address — no port mapping needed.

**`container-runtime-linux`** — one instance per container. This is the process that actually owns the `VZVirtualMachine`. It uses AVF to boot the micro-VM, connects to vminitd over vsock, and manages the container's lifecycle.

#### 5. Networking

Each container gets a **dedicated IP address** from a managed subnet. On macOS 26, containers on the same network can communicate directly.

```
macOS 15 (Sequoia):          macOS 26 (Tahoe):
┌──────┐  ┌──────┐          ┌──────┐  ┌──────┐
│ VM 1 │  │ VM 2 │          │ VM 1 │──│ VM 2 │
│ .64.2│  │ .64.3│          │ .64.2│  │ .64.3│
└──┬───┘  └──┬───┘          └──┬───┘  └──┬───┘
   │         │  isolated        └────┬────┘  shared vmnet
   ↓         ↓                      ↓
  Host      Host                   Host
```

Port publishing (`-p 8080:80`) uses userspace TCP/UDP forwarders that proxy from the host to the container's IP.

The API server also runs DNS servers: one for container hostname resolution (container-to-container), one that forwards to the host's resolvers (internet access).

#### 6. Volume and mount management

Three mount types:

| Type | Flag | How it works |
|---|---|---|
| **Host directory** | `-v /host:/guest` | VirtioFS share — same AVF primitive Lima uses |
| **Named volume** | `-v mydata:/guest` | ext4 block device image, created by the Swift EXT4 formatter |
| **tmpfs** | `--tmpfs /path` | In-memory filesystem, created by vminitd inside the VM |

Named volumes persist across container restarts. Host directory mounts use VirtioFS for near-native performance. Both are the same AVF primitives that Lima uses — the difference is in the management layer on top.

### The full apple/container stack

```
container run -v ./project:/work my-image nix develop
      |
[container CLI]
      |  XPC
[container-apiserver]
  ├── [container-core-images]
  │     └── Pull OCI image → unpack layers → write ext4 → APFS clone
  ├── [container-network-vmnet]
  │     └── Allocate IP, create vmnet interface
  └── [container-runtime-linux]  (one per container)
        |
   [Apple Virtualization Framework]
     ├── VirtioBlockDevice (initfs.ext4 + rootfs.ext4 + volumes)
     ├── VirtioFileSystem (host directory mounts via VirtioFS)
     ├── VirtioNetwork (per-VM NAT or shared vmnet)
     ├── VirtioSocket (vsock for gRPC to vminitd)
     └── VirtioEntropy, MemoryBalloon
        |
   [Micro-VM]
     └── vminitd (PID 1, Swift/musl static binary)
           ├── Mount rootfs, volumes, virtiofs shares
           ├── Configure network, DNS, hostname
           ├── Launch container process
           ├── Stream stdout/stderr over vsock
           └── Report exit code and statistics
```

---

## Side-by-Side: What Each Layer Provides

| Need | AVF | Lima adds... | apple/container adds... |
|---|---|---|---|
| Boot Linux | `VZLinuxBootLoader` | Auto-selects boot method, converts images | Custom kernel with minimal config |
| Disk storage | Raw block device only | qcow2 conversion, disk management | Swift EXT4 creation, APFS CoW clones |
| Networking | NAT (no port forwarding) | gvisor-tap-vsock userspace stack, port scanning + forwarding | Per-container IP via vmnet, DNS |
| File sharing | VirtioFS device | Mount management, fstab generation, inotify relay | Mount parsing, volume management |
| Talk to guest | vsock streams (raw bytes) | Guest agent (gRPC): ports, time, inotify | vminitd (gRPC): process mgmt, stats |
| User accounts | Nothing | cloud-init: user, SSH keys, sudo | vminitd: process user/env/workdir |
| Remote access | Serial console | SSH over vsock, control master | gRPC over vsock (no SSH needed) |
| Run commands | Nothing | `limactl shell` → SSH | `container exec` → gRPC → vminitd |
| Manage VMs | In-process object | Instance dirs, host agent, limactl CLI | XPC services, launchd, apiserver |
| Container images | Nothing | containerd/nerdctl inside guest | Full OCI pipeline on host |
| Persist state | Nothing | VM stays running, disk persists | Volumes persist, containers are ephemeral |

---

## What's genuinely novel in apple/container?

Most differences between Lima and apple/container are implementation choices, not new capabilities. Both build on the same AVF primitives. But a few things are genuinely novel:

### 1. APFS copy-on-write clones for instant container creation

When you `container run`, it doesn't copy the image — it calls `clonefile()` on the ext4 snapshot. This is an APFS-level CoW copy that completes in microseconds regardless of image size. The container starts with its own writable "copy" that shares physical storage with the snapshot until bytes diverge.

Lima doesn't need this (one persistent VM), but it's a real capability difference when spinning up many containers from the same image.

### 2. Swift EXT4 formatter

macOS can't mount or create ext4. apple/container wrote a pure-Swift ext4 implementation so the host can create Linux root filesystems and volumes without any Linux tooling. Lima sidesteps this by downloading pre-built disk images.

### 3. Sub-second boot via extreme minimalism

The speed difference isn't AVF — it's what's inside the VM. Lima boots a full Linux distro (systemd, cloud-init, sshd, guest agent — dozens of services, ~10s). apple/container boots vminitd — a single static binary compiled from Swift via musl. No libc, no coreutils, no shell. PID 1 is the only process until the container's command starts. Result: sub-second boot.

### 4. No SSH — gRPC over vsock only

Lima's primary interface is SSH (with the guest agent as a sidecar). apple/container never uses SSH — everything goes through gRPC over vsock to vminitd. No SSH server, no key management, no sshd startup time.

### What's NOT actually different

- **VirtioFS** — same AVF primitive, same performance
- **Networking** — both use the same vmnet/NAT primitives, just with different management layers
- **vsock** — both use it for host↔guest communication
- **Disk attachment** — both end up attaching raw block devices via `VZVirtioBlockDeviceConfiguration`

---

## Choosing Between Them

### Lima when...

- You want a **persistent Linux environment** that accumulates state
- You need a **full NixOS system** with systemd and services
- You want something that **works today** on macOS 13+
- You're building on an **existing ecosystem** (CNCF, containerd, Docker-compatible)
- You want **Intel Mac support** (via QEMU fallback)

### apple/container when...

- You want **ephemeral containers with persistent volumes** (clean rootfs, durable data)
- You need **sub-second startup** for frequent spin-up/tear-down
- You want **hypervisor-level isolation** between containers
- You're building a **macOS-native app** and want to embed VMs (Swift package)
- You're on **macOS 26+** and OK with pre-1.0 software

### Both when...

- You want to understand what's possible on macOS for containerized/virtualized dev environments
- You're exploring the design space for a tool that wraps either (or both) of them

---

## For the Nix Dev Shell Use Case

The specific question that motivated this exploration: *Can we use these tools to provide Nix dev shells without requiring Nix on the developer's Mac?*

### Lima approach (validated in spike 1)

```
brew install lima          # one-time
limactl start nixos-vz     # boots NixOS VM, ~10s
limactl shell nixos-vz     # SSH in
nix develop                # 0.5s warm, 20s cold
```

The VM stays running. Your project is mounted via VirtioFS. Cold start is slow because packages download from cache.nixos.org. But once cached, it's near-instant. The VM is a pet — state accumulates.

### apple/container approach (the path forward)

The key insight: **named volumes persist across container runs.** This solves the "ephemeral Nix store" problem.

```bash
# First run — cold start, downloads packages (~20s for nix, <1s for VM boot)
container run -it \
  -v nix-store:/nix \
  -v ./project:/work \
  nixos/nix sh -c 'cd /work && nix develop'

# Second run — everything warm (<1s boot + <1s nix develop)
container run -it \
  -v nix-store:/nix \
  -v ./project:/work \
  nixos/nix sh -c 'cd /work && nix develop'
```

What happens:
1. `nix-store` is a **named volume** — a persistent ext4 block device image created by the Swift EXT4 formatter, stored at `<appRoot>/volumes/nix-store/volume.img`
2. First run: VM boots in <1s, Nix downloads packages into the volume (~20s, network-bound)
3. Volume survives container exit — `/nix/store` and `/nix/var/nix/db` persist
4. Second run: VM boots fresh (<1s), volume reattaches, `nix develop` finds cached packages (<1s)
5. Rootfs is ephemeral (APFS clone, discarded on exit) — clean environment every time
6. Only `/nix` persists — the best of both worlds

**Constraint:** Only one container can mount a named volume at a time (ext4 mounted by two VMs = corruption). For the "one dev shell at a time" use case, that's fine. For parallel dev shells on different projects, you'd use separate volumes (`nix-store-projectA`, `nix-store-projectB`) — or a shared binary cache to seed them.

### Why apple/container is the more interesting path

| Factor | Lima | apple/container |
|---|---|---|
| Boot time | ~10s | **<1s** |
| Environment | Persistent VM (pet) | **Ephemeral rootfs + persistent volumes** |
| Nix store | Accumulates in VM disk | **Persistent named volume** |
| Clean state | Must manually clean | **Automatic — rootfs is fresh each run** |
| Embeddable | Shell out to `limactl` | **Swift package, native macOS integration** |
| Dev shell UX | SSH into running VM | **`container run` → in shell → exit → gone** |

The apple/container model maps more naturally to the "just drop into a dev shell" UX: each invocation is clean, the Nix store persists transparently, and you don't manage a background VM.

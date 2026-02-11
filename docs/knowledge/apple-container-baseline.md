# apple/container + Nix Dev Shell Setup

## What This Covers
How to run Nix dev shells inside apple/container micro-VMs with persistent /nix store
via named volumes and VirtioFS project mounts.

## Prerequisites
- macOS 26+ (Tahoe), Apple Silicon
- Xcode 26+
- apple/container v0.9.0+ (built from source with release config)

## Critical: Must Use Release Build
Debug builds of apple/container cannot unpack the nixos/nix image (70 OCI layers).
The ext4 unpacker in debug mode is too slow, causing XPC connection timeouts
(CancellationError). Always build with:
```bash
BUILD_CONFIGURATION=release make all
```

## Setup Steps

### 1. Build and start
```bash
cd downloads/container
git checkout 0.9.0
BUILD_CONFIGURATION=release make all
bin/container system start --enable-kernel-install
```

### 2. Seed the /nix volume
The nixos/nix image puts ALL binaries in `/nix/store`. Mounting an empty volume
at `/nix` hides everything. Must seed first:
```bash
bin/container run --rm -v nix-store:/nix-persist nixos/nix \
  sh -c 'cp -a /nix/* /nix-persist/'
```
This takes ~8s and only needs to be done once per volume.

### 3. Run nix develop
```bash
bin/container run --rm \
  -v nix-store:/nix \
  -v /path/to/project:/work \
  nixos/nix \
  sh -c 'cd /work && nix --extra-experimental-features "nix-command flakes" develop'
```

### 4. Detached mode + exec
```bash
# Start detached
bin/container run -d --name mydev \
  -v nix-store:/nix \
  -v /path/to/project:/work \
  nixos/nix sleep infinity

# Exec into it (must use sh -c for PATH)
bin/container exec mydev sh -c 'cd /work && nix develop'

# Clean up
bin/container stop mydev && bin/container rm mydev
```

## Performance Data (v0.9.0, release build)
- Boot: ~0.7s
- Warm nix develop: ~1.2s
- Cold nix develop: ~26s (network-bound)
- Volume: 512GB sparse ext4, 1.8GB actual after basic dev shell
- VirtioFS: <1ms reads, 3ms write+read+delete, 64ms for 100 stats

## Known Issues

### container exec doesn't inherit image env vars
Direct `container exec <name> nix --version` fails because exec doesn't set
the image's PATH. Always use `sh -c` wrapper.

### Experimental features not enabled by default
nixos/nix image requires `--extra-experimental-features "nix-command flakes"`.
Can persist by writing nix.conf to the volume:
```bash
mkdir -p /nix/etc/nix
echo 'experimental-features = nix-command flakes' > /nix/etc/nix/nix.conf
```

### No brew cask
Must build from source or use .pkg from GitHub releases (requires sudo).

## Volume Management
- Volumes persist at: `~/Library/Application Support/com.apple.container/volumes/`
- List: `container volume list`
- Inspect: `container volume inspect nix-store`
- Delete: `container volume rm nix-store` (destroys all cached packages)
- Multiple projects can share one volume (packages accumulate)
- Or use per-project volumes for isolation: `-v nix-store-projectA:/nix`

## Architecture Notes
- Each `container run` boots a fresh micro-VM (vminitd as PID 1)
- Rootfs is an APFS CoW clone, discarded on exit
- Named volume is a persistent ext4 block device image
- VirtioFS uses same AVF primitive as Lima — identical performance
- XPC services: apiserver, core-images, network-vmnet, runtime-linux (one per container)

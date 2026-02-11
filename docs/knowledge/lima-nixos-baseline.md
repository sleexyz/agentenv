# Lima + NixOS: VZ Driver + VirtioFS Setup Guide

## What This Covers
How to run NixOS inside Lima on macOS using the VZ (Virtualization.framework) driver
with VirtioFS file sharing, and execute `nix develop` against host-mounted flakes.

## Working Configuration

### Lima YAML
```yaml
vmType: vz

images:
- location: "https://github.com/nixos-lima/nixos-lima/releases/download/v0.0.3/nixos-lima-v0.0.3-aarch64.qcow2"
  arch: "aarch64"
  digest: "sha512:809bd6bf46e27719eb69cc248e31a6c98725415976f8f0111b86228148a4379ea05e7405930c086487c9d51961e8776f61744175f33423ce3508e74a7f1a87c4"

cpus: 4
memory: "4GiB"
disk: "20GiB"

mounts:
- location: "~"
  writable: false
- location: "/path/to/project"
  mountPoint: "/path/to/project"  # same path as host
  writable: true

containerd:
  system: false
  user: false
```

### Critical: Do NOT use `plain: true`
Setting `plain: true` disables:
- Lima guest agent (needed for VirtioFS mount orchestration)
- VirtioFS mount setup
- Port forwarding
- Cloud-init style provisioning

The guest agent binary is shipped inside Lima's cidata ISO, not baked into the
VM image. When `plain: true` is set, Lima excludes the guest agent from cidata,
causing `lima-guestagent.service` to fail with "No such file or directory".

## How Lima VZ Boot Works

1. `limactl create`: Downloads qcow2 image, converts to raw (VZ requires raw)
2. `limactl start`: Boots VM via Virtualization.framework
3. NixOS `lima-init.service`: Reads cidata, creates user, sets up SSH keys
4. Lima guest agent: Starts from cidata binary, handles VirtioFS mounts + port forwarding
5. Lima host agent: Detects guest agent via vsock, confirms readiness

## Performance Characteristics (Apple Silicon, macOS 26)

| Metric | Value |
|--------|-------|
| Boot time | ~10s |
| Warm `nix develop` | 0.4-0.6s |
| Cold `nix develop` (network fetch) | ~20s |
| VirtioFS file read | <1ms |
| VirtioFS file write | <1ms |
| VirtioFS stat (per call) | ~1.1ms |
| VirtioFS find 1328 files | 119ms |
| Broad home dir traversal | Slow (25s+) |

## Gotchas

1. **NixOS user home**: `/home/<user>.linux` (not `/home/<user>`)
2. **9p is broken**: Linux 6.9-6.11 have 9p bugs; VZ+VirtioFS is the right choice
3. **Mount paths**: Use the same path in guest as host for `nix develop` compatibility
4. **Scoped mounts**: Broad home directory traversals on VirtioFS are slow; mount only what you need
5. **qcow2→raw**: Lima auto-converts; takes ~2s, cached for subsequent creates

## Software Versions Tested
- macOS 26.2 (Darwin 25.2.0), Apple Silicon
- Lima 2.0.2
- nixos-lima v0.0.3 (NixOS 25.11, kernel 6.16.3, Nix 2.28.4)

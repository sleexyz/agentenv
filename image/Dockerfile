FROM alpine:latest AS busybox-src

FROM nixos/nix:latest

# Enable flakes and nix-command by default
COPY nix.conf /etc/nix/nix.conf

# Copy busybox + musl dynamic linker from Alpine — needed because mounting an
# empty volume at /nix shadows ALL binaries (including /bin/sh which symlinks
# into /nix/store). The entrypoint must use a shell that exists outside /nix.
COPY --from=busybox-src /bin/busybox /busybox
COPY --from=busybox-src /lib/ld-musl-aarch64.so.1 /lib/ld-musl-aarch64.so.1

# Backup /nix so we can seed an empty volume at runtime
RUN cp -a /nix /nix-seed

# Entrypoint script uses /busybox sh — works even when /nix is an empty volume
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /work

ENTRYPOINT ["/busybox", "sh", "/entrypoint.sh"]

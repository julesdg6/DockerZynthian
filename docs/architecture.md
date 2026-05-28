# Architecture

DockerZynthian wraps a QEMU VM inside a container and boots an official ZynthianOS disk image.

## Flow

1. `download-zynthian-image.sh`
   - fetches latest stable image archive from `https://os.zynthian.org/` (or uses `ZYNTHIAN_IMAGE_URL`).
2. `prepare-image.sh`
   - extracts `.img` from archive
   - stores persistent disk at `/data/zynthian.img`
   - extracts boot files (`kernel8.img`, `*.dtb`) from partition 1 to `/data/bootfiles`
3. `run-qemu.sh`
   - starts `qemu-system-aarch64`
   - emulates `raspi4b` by default; detects supported machines via `qemu-system-aarch64 -machine help` and automatically falls back to `raspi3b` (with a warning) when `raspi4b` is unavailable
   - forwards guest service ports to container ports

## Persistence

- `/data/zynthian.img` contains guest system state.
- `/data/downloads` keeps source archives.
- `/data/bootfiles` keeps extracted kernel/DTB files.

## Networking model

QEMU uses user-mode networking with host forwards to expose services.

## Honest limitations

- Pi 4 support is the primary target; Pi 3 is used automatically as a fallback when `raspi4b` is not supported by the host QEMU; Pi 5 is not validated.
- GPIO/HAT, GPU acceleration, and hard real-time audio are out of scope.

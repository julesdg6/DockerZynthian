# Architecture

DockerZynthian wraps a QEMU VM inside a container and boots an official ZynthianOS disk image.

## Flow

1. `download-zynthian-image.sh`
   - fetches latest stable image archive from `https://os.zynthian.org/` (or uses `ZYNTHIAN_IMAGE_URL`).
2. `prepare-image.sh`
   - extracts `.img` from archive
   - stores persistent disk at `${IMAGE_PATH}` (default `/data/zynthian.img`)
   - extracts boot files (`kernel8.img`, `*.dtb`) from partition 1 to `${BOOT_DIR}` (default `/data/bootfiles`)
3. `run-qemu.sh`
   - starts `qemu-system-aarch64`
   - emulates `raspi4b` by default; detects supported machines via `qemu-system-aarch64 -machine help` and automatically falls back to `raspi3b` (with a warning) when `raspi4b` is unavailable
   - forwards guest service ports to container ports

## Persistence

- `${IMAGE_PATH}` contains guest system state.
- `${DOWNLOAD_DIR}` keeps source archives.
- `${BOOT_DIR}` keeps extracted kernel/DTB files.
- `run-qemu.sh` / `prepare-image.sh` search both `${DOWNLOAD_DIR}` and `${DATA_DIR}` for existing archives before downloading.

## Networking model

QEMU uses user-mode networking with host forwards to expose services.

## Honest limitations

- Pi 4 support is the primary target; Pi 3 is used automatically as a fallback when `raspi4b` is not supported by the host QEMU; Pi 5 is not validated.
- GPIO/HAT, GPU acceleration, and hard real-time audio are out of scope.

# DockerZynthian

Run the **official ZynthianOS Raspberry Pi image** inside Docker/Unraid using QEMU ARM emulation.

> Goal: first reliable milestone is reaching **Webconf** from a browser on the host.

## Status and scope

- Uses official image from `https://os.zynthian.org/` (downloaded at runtime).
- Primary target: **x86_64 Unraid**.
- Also supports standard Docker / docker compose on Linux.
- Emulation target:
  - `pi4` (default, practical target)
  - `pi3` (minimum supported)
  - `pi5` currently falls back to `pi4` (QEMU support is limited)
- Persistent state via `/data/zynthian.img`.
- Configurable RAM via `MEMORY_MB`.
- Forwards guest services to container ports:
  - SSH guest `22` -> container `${SSH_PORT:-2222}`
  - Webconf / web UI guest `80` -> container `${WEBCONF_PORT:-8080}`
  - HTTPS guest `443` -> container `${HTTPS_PORT:-8443}`
  - noVNC guest `6080` -> container `${NOVNC_PORT:-6080}`
  - VNC guest `5900` -> container `${VNC_PORT:-5900}`

## Quick start (docker compose)

```bash
docker compose up --build
```

Then open:

- `http://localhost:8080` (Webconf / web UI)
- `http://localhost:6080` (if noVNC is active in the guest)
- `ssh -p 2222 root@localhost`

## Manual Docker run

```bash
docker build -t dockerzynthian .

docker run --rm -it \
  --name dockerzynthian \
  --privileged \
  -e MEMORY_MB=3072 \
  -e PI_MODEL=pi4 \
  -e SSH_PORT=2222 \
  -e WEBCONF_PORT=8080 \
  -e HTTPS_PORT=8443 \
  -e NOVNC_PORT=6080 \
  -e VNC_PORT=5900 \
  -v dockerzynthian-data:/data \
  -p 2222:2222 \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 6080:6080 \
  -p 5900:5900 \
  dockerzynthian
```

## Image workflow

The container entrypoint (`scripts/run-qemu.sh`) does:

1. Download latest stable official image (`scripts/download-zynthian-image.sh`) unless `ZYNTHIAN_IMAGE_URL` is set.
2. Extract and prepare raw disk image (`scripts/prepare-image.sh`).
3. Boot QEMU with Raspberry Pi model emulation.

## Unraid

Template is included at `unraid/DockerZynthian.xml`.

See docs:

- `docs/architecture.md`
- `docs/unraid.md`
- `docs/usb-passthrough.md`
- `docs/troubleshooting.md`

## Important limitations (honest status)

- No claim of GPIO/HAT compatibility.
- No claim of Pi GPU/display acceleration.
- No claim of hard real-time audio performance.
- Pi 5 is **not** validated; mapped to pi4 fallback currently.
- USB audio/MIDI passthrough can work depending on host privileges, device permissions, and guest support.

## Useful environment variables

- `MEMORY_MB` (default `2048`)
- `PI_MODEL` (`pi3`, `pi4`, `pi5`)
- `ZYNTHIAN_IMAGE_URL` (optional explicit image archive URL)
- `SSH_PORT`, `WEBCONF_PORT`, `HTTPS_PORT`, `NOVNC_PORT`, `VNC_PORT`
- `DISK_EXPAND_GB` (optional, expand persistent image)

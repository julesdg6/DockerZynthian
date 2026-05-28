# DockerZynthian

Run the **official ZynthianOS Raspberry Pi image** inside Docker/Unraid using QEMU ARM emulation.

> Goal: first reliable milestone is reaching **Webconf** from a browser on the host.

## Status and scope

- Uses official image from `https://os.zynthian.org/` (downloaded at runtime).
- Primary target: **x86_64 Unraid**.
- Also supports standard Docker / docker compose on Linux.
- Emulation target:
  - `pi3` (default, validated)
  - `pi4` (used when supported by host QEMU)
  - `pi5` currently falls back to `pi4` (QEMU support is limited)
- Persistent state via `/data/zynthian.img`.
- Configurable RAM via `MEMORY_MB` (raspi3 is clamped to 1024MB by QEMU rules).
- QEMU forwards guest services to fixed container ports:
  - SSH guest `22` -> container `2222`
  - Webconf / web UI guest `80` -> container `8080`
  - HTTPS guest `443` -> container `8443`
  - noVNC guest `6080` -> container `6080`
  - VNC guest `5900` -> container `5900`
- Docker/Compose publishes those container ports to configurable host ports.

## Full Docker installation

### Prerequisites

- Docker Engine 24+ (or Docker Desktop) on a **Linux x86_64** host.
- `docker compose` plugin (v2) — included with recent Docker Desktop and Docker Engine installs.
- Internet access for the first-run ZynthianOS image download (~1–2 GB compressed).
- At least **4 GB RAM** available for the container, and **20 GB free disk** for the persistent image.

### Option A — docker compose (recommended)

1. **Clone this repository:**

   ```bash
   git clone https://github.com/julesdg6/DockerZynthian.git
   cd DockerZynthian
   ```

2. **Start the container (builds locally on first run):**

   ```bash
   docker compose up --build
   ```

   Run compose from the repository root so `${ZYNTHIAN_DATA_PATH:-./data}` mounts correctly.

3. **On first start** the container automatically downloads and prepares the official ZynthianOS Raspberry Pi image. This takes several minutes depending on your connection speed. Watch the logs for progress:

   ```bash
   docker compose logs -f
   ```

4. **Access the services once the guest has booted:**

   | Service            | URL / command                          |
   |--------------------|----------------------------------------|
   | Webconf / web UI   | `http://localhost:8080`                |
   | noVNC (if active)  | `http://localhost:6080`                |
   | SSH into guest     | `ssh -p 2222 root@localhost`           |

5. **Stop and restart:**

   ```bash
   docker compose down   # stop (persistent image in ./data is preserved)
   docker compose up     # restart without rebuilding
   ```

### Option B — manual `docker run`

Use this if you prefer not to use Compose or want full control over every flag.

1. **Build the image:**

   ```bash
   docker build -t dockerzynthian .
   ```

2. **Run the container:**

   ```bash
   docker run --rm -it \
     --name dockerzynthian \
     --privileged \
     -e PI_MODEL=pi3 \
     -e MEMORY_MB=1024 \
     -e DISK_SIZE_GB=16 \
     -e EMULATION_STUBS=1 \
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

   Replace `-v dockerzynthian-data:/data` with `-v /path/on/host:/data` if you prefer a bind mount.

3. **Access the services** using the same URLs listed in Option A.

### Using a pre-built image from Docker Hub

If you don't want to build locally, pull the published image directly:

```bash
docker pull julesdg6/dockerzynthian:latest

docker run --rm -it \
  --name dockerzynthian \
  --privileged \
  -e PI_MODEL=pi3 \
  -e MEMORY_MB=1024 \
  -e DISK_SIZE_GB=16 \
  -e EMULATION_STUBS=1 \
  -v dockerzynthian-data:/data \
  -p 2222:2222 \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 6080:6080 \
  -p 5900:5900 \
  julesdg6/dockerzynthian:latest
```

## Image workflow

The container entrypoint (`scripts/run-qemu.sh`) does:

1. Download latest stable official image (`scripts/download-zynthian-image.sh`) unless `ZYNTHIAN_IMAGE_URL` is set.
2. Extract and prepare raw disk image (`scripts/prepare-image.sh`).
3. Boot QEMU with Raspberry Pi model emulation.

Helper scripts:

- `scripts/reset-image.sh` (`--all` also removes downloads cache)
- `scripts/check-qemu-support.sh` (prints supported raspi machines + recommended `PI_MODEL`)
- `scripts/resize-image.sh` (resizes an existing raw image to `DISK_SIZE_GB`)

## Unraid

Template is included at `unraid/DockerZynthian.xml`. The Zynthian logo (`docs/icon.png`) is referenced by the template and displayed automatically in the Unraid Docker tab.

See docs:

- `docs/unraid.md` — full setup steps, wget icon instructions, and Community Apps import guide
- `docs/architecture.md`
- `docs/usb-passthrough.md`
- `docs/troubleshooting.md`

## Confirmed current status

Working:

- Boots official ZynthianOS image automatically on first run.
- SSH works through host port `2222`.
- Webconf works through host port `8080` when emulation stubs are enabled.
- Persistent storage works via `/data/zynthian.img`.
- Pi3 / `raspi3b` emulation works.

Known limitations:

- No claim of GPIO/HAT compatibility.
- No claim of Pi GPU/display acceleration.
- No claim of hard real-time audio performance.
- Pi4/Pi5 depend on host QEMU machine support.
- raspi3b is limited to 1GB RAM in QEMU.
- USB audio is not configured yet.
- USB MIDI is not configured yet.
- GPIO/HAT/display hardware is emulated/stubbed, not real hardware.
- Webconf requires emulation stubs when I2C devices are absent.

## Useful environment variables

- `MEMORY_MB` (default `1024`, auto-clamped on raspi3*)
- `PI_MODEL` (`pi3`, `pi4`, `pi5`, with auto machine fallback)
- `DISK_SIZE_GB` (default `16`, power-of-two target)
- `EMULATION_STUBS` (`1` enables guest I2C/i2cdetect stubs for Webconf)
- `PUID`, `PGID` (default `99:100`, ownership fix for `/data`)
- `ZYNTHIAN_IMAGE_URL` (optional explicit image archive URL)
- `SSH_PORT`, `WEBCONF_PORT`, `HTTPS_PORT`, `NOVNC_PORT`, `VNC_PORT` (host publish ports in compose)
- `DATA_DIR`, `DOWNLOAD_DIR`, `IMAGE_PATH`, `BOOT_DIR` (advanced path overrides; defaults under `/data`)
- `ZYNTHIAN_DATA_PATH` (compose host bind path for container `/data`, default `./data`)

## First run quickstart

```bash
docker compose up --build
```

or

```bash
docker run -it --privileged \
  -e PI_MODEL=pi3 \
  -e MEMORY_MB=1024 \
  -e DISK_SIZE_GB=16 \
  -e EMULATION_STUBS=1 \
  -v "$(pwd)/data:/data" \
  -p 2222:2222 \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 6080:6080 \
  -p 5900:5900 \
  dockerzynthian
```

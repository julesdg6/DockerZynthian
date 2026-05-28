# Display / Framebuffer Support

## Background

QEMU does **not** accurately emulate Raspberry Pi HDMI or VideoCore GPU hardware.
The goal of these features is **not** true HDMI emulation — it is simply to provide
enough virtual framebuffer or display presence so that Zynthian UI and its
browser-based noVNC can start.

## DISPLAY_MODE

Controls QEMU's own display output.  Set via the `DISPLAY_MODE` environment variable.

| Value | Behaviour |
|-------|-----------|
| `none` (default) | Headless; QEMU runs with `-nographic`.  No QEMU VNC server runs; container port 5901 is inactive. |
| `vnc` | QEMU starts a built-in VNC server on container port **5901** (VNC display `:1`).  Connect with any VNC viewer to `HOST:5901`.  **Note:** raspi machines have no emulated GPU, so the VNC image will appear blank/black.  It is still useful for debug and may help the guest kernel detect a display. |
| `gtk` | QEMU opens a GTK window.  Only usable if a host `DISPLAY` is forwarded into the container (e.g. via an X11 socket bind-mount).  Not supported in Unraid or standard headless setups. |

### Important distinction: port 5901 vs port 5900

| Port | What it is |
|------|------------|
| **5900** | Zynthian's own VNC server **inside** the guest, forwarded via QEMU user networking. |
| **5901** | QEMU's **built-in** VNC display server — only active when `DISPLAY_MODE=vnc`. |

These are completely separate services.  Port 5901 is the QEMU machine's display
(what a physical monitor would show); port 5900 is the VNC server running inside
the Zynthian OS.

### Example: enable QEMU VNC display

```bash
# docker compose
DISPLAY_MODE=vnc docker compose up

# docker run
docker run --rm -it --privileged \
  -e DISPLAY_MODE=vnc \
  -p 5901:5901 \
  -p 8080:8080 \
  -p 2222:2222 \
  -v dockerzynthian-data:/data \
  dockerzynthian
```

Then connect with any VNC client to `HOST:5901`.

> **Security note:** `DISPLAY_MODE=vnc` binds QEMU's VNC server to `0.0.0.0:5901`
> (all container interfaces).  The port is published to the host via Docker's port
> mapping.  This is intentional for a debug/development feature but means the
> QEMU display is reachable from any host that can reach the Docker host on that
> port.  There is no VNC password configured.  Use a firewall or restrict the
> host binding (e.g. `-p 127.0.0.1:5901:5901`) if the host is exposed to
> untrusted networks.

## ENABLE_FAKE_DISPLAY

Setting `ENABLE_FAKE_DISPLAY=1` installs a guest-side systemd service
(`dockerzynthian-fake-display.service`) into the Zynthian image during the
image-preparation phase.

When the guest boots that service:

1. Checks whether `/dev/fb0` or `/dev/dri/card0` already exists.
2. If a real framebuffer is present, exits without doing anything.
3. If no real framebuffer is found, attempts to start **Xvfb** on display `:0`
   with a 1280 × 720 × 24-bit virtual screen.
4. If Xvfb starts successfully, writes `DISPLAY=:0` to `/etc/environment` so
   that Zynthian UI and other X11-dependent services inherit the display.
5. Logs diagnostic output (framebuffer state, DRI devices, running X servers)
   to the journal/stderr for troubleshooting.

### Prerequisite

`xvfb` must be installed inside the ZynthianOS image.  If the package is absent
the service exits cleanly with a warning.  You can install it via SSH:

```bash
ssh -p 2222 root@HOST apt-get install -y xvfb
```

After installing, reboot the guest (or start the service manually):

```bash
systemctl start dockerzynthian-fake-display
```

### Kernel cmdline hint

When `ENABLE_FAKE_DISPLAY=1` the kernel command line also receives
`drm_kms_helper.fbdev_emulation=1`.  This instructs the kernel's DRM subsystem
to create an `fbdev` emulation layer if a DRM driver is active — potentially
making `/dev/fb0` appear even without real VideoCore hardware.  In practice this
depends on what DRM drivers the ZynthianOS kernel loads for the QEMU machine.

### Example: enable fake display

```bash
# First-time image preparation with fake display stubs installed:
ENABLE_FAKE_DISPLAY=1 docker compose up --build

# Or with docker run:
docker run --rm -it --privileged \
  -e EMULATION_STUBS=1 \
  -e ENABLE_FAKE_DISPLAY=1 \
  -p 8080:8080 \
  -p 6080:6080 \
  -p 2222:2222 \
  -v dockerzynthian-data:/data \
  dockerzynthian
```

> **Note:** `ENABLE_FAKE_DISPLAY` only modifies the image during first-time
> preparation (or when the image is absent).  To re-apply the stubs to an
> existing image, delete `/data/bootfiles` and restart — `prepare-image.sh`
> will re-extract boot files and re-run all stubs.  The image itself is kept.

## Checking framebuffer state inside the guest

SSH into the guest and run:

```bash
ssh -p 2222 root@HOST

# Check framebuffer devices:
ls /dev/fb*
ls /dev/dri/

# Check running display-related processes:
pgrep -a Xvfb
pgrep -a Xorg
pgrep -a x11vnc

# Check noVNC / VNC services:
systemctl status novnc 2>/dev/null || true
systemctl status vncserver 2>/dev/null || true
```

## Known limitations

- QEMU `raspi3b` / `raspi4b` machines **do not** emulate VideoCore IV/VI.
  There is no GPU, no HDMI output, and no hardware-accelerated framebuffer.
- `DISPLAY_MODE=vnc` gives a QEMU-level VNC view that will be blank/black
  unless the guest kernel renders something into an emulated display device.
- Xvfb provides a software-only X11 display.  It is sufficient for most
  Zynthian UI / noVNC scenarios but does not provide audio or GPIO access.
- `DISPLAY_MODE=gtk` requires a host X11/Wayland display forwarded into the
  container and is not supported in Unraid or headless server environments.

# Troubleshooting

## Webconf not reachable

- Check container logs for QEMU boot progress.
- Wait longer on first boot.
- Confirm port mapping (`8080` by default).
- Try `ssh -p 2222 root@host` to verify guest network path.

## Image download fails

- Set `ZYNTHIAN_IMAGE_URL` explicitly to a known official image archive URL.
- Verify outbound network access from Docker host.

## DTB/kernel extraction failures

- Remove `/data/bootfiles` and restart container.
- Ensure downloaded archive contains a valid Raspberry Pi boot partition.

## QEMU boots but service ports stay closed

- Guest init may still be running.
- Confirm target service is enabled in guest image.
- Try `PI_MODEL=pi3` as fallback.

## USB device not available

- Verify container is privileged.
- Verify `/dev/bus/usb` is mapped.
- Replug device and restart container.

## Zynthian UI / noVNC not working (no display)

QEMU does not emulate Raspberry Pi HDMI/VideoCore.  Without a framebuffer or
virtual display, the Zynthian UI and noVNC may fail to start.

Steps to diagnose and fix:

1. **Check display state inside the guest:**

   ```bash
   ssh -p 2222 root@HOST
   ls /dev/fb*           # should show /dev/fb0 if framebuffer present
   ls /dev/dri/          # DRM devices
   pgrep -a Xvfb         # virtual framebuffer
   pgrep -a Xorg
   ```

2. **Enable the fake display stub:**
   Set `ENABLE_FAKE_DISPLAY=1` and ensure the image is re-prepared (remove
   `/data/bootfiles` and restart to force re-extraction and stub installation):

   ```bash
   ENABLE_FAKE_DISPLAY=1 docker compose up
   ```

3. **Install Xvfb in the guest** if the fake display service reports it is missing:

   ```bash
   ssh -p 2222 root@HOST apt-get install -y xvfb
   systemctl start dockerzynthian-fake-display
   ```

4. **Enable QEMU display VNC** for debug visibility:

   ```bash
   DISPLAY_MODE=vnc docker compose up
   # Then connect to HOST:5901 with a VNC viewer.
   ```

   The QEMU VNC image will be blank/black (no GPU emulation), but this mode
   may help the guest kernel detect a display device.

See [docs/display.md](display.md) for full details on all display options.

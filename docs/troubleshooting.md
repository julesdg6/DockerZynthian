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

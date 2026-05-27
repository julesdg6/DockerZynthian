# Unraid setup

1. Build/publish image (or point template to your own registry tag).
2. In Unraid Community Apps, import `unraid/DockerZynthian.xml`.
3. Keep container **Privileged=true**.
4. Map `/data` to `/mnt/user/appdata/dockerzynthian`.
5. Start container and wait for first boot preparation (download + extract).
6. Open Web UI at `http://<unraid-ip>:8080`.

## Recommended initial settings

- `MEMORY_MB=2048` (increase to 3072/4096 if host allows)
- `PI_MODEL=pi4`

## Notes

- First boot is slow due to image download/extraction and guest initialization.
- If automatic image discovery fails, set `ZYNTHIAN_IMAGE_URL` in template variables.

# Unraid setup

## Installing via Community Applications (CA)

1. In Unraid, open **Apps** (Community Applications plugin required).
2. Search for **DockerZynthian** or click **Add Container** and paste the template URL:
   ```
   https://raw.githubusercontent.com/julesdg6/DockerZynthian/main/unraid/DockerZynthian.xml
   ```
3. Keep **Privileged** set to `true`.
4. Set the **AppData** path to `/mnt/user/appdata/dockerzynthian` (default).
5. (Optional) set **Download Cache** to a separate persistent folder if you want archive caching outside the main AppData tree.
6. (Optional, advanced) override `DOWNLOAD_DIR`, `IMAGE_PATH`, or `BOOT_DIR` template variables for custom layout.
7. Adjust **RAM MB** and **Pi Model** as needed (see recommended settings below).
8. Click **Apply** and wait for the container to pull the image.
9. On first start the container downloads and prepares the ZynthianOS image — this may take several minutes depending on your connection speed.
10. Open the Web UI at `http://<unraid-ip>:8080`.

## Adding the Zynthian icon on Unraid 7

Unraid 7 looks for container icons in `/boot/config/plugins/dockerMan/images/`. Place the Zynthian logo there so it appears in the Docker tab.

Run the following in the Unraid terminal (or via SSH):

```bash
mkdir -p /boot/config/plugins/dockerMan/images
wget -O /boot/config/plugins/dockerMan/images/DockerZynthian.png \
  https://raw.githubusercontent.com/julesdg6/DockerZynthian/main/docs/icon.png
```

`wget` prints a summary line such as `'DockerZynthian.png' saved [9420/9420]` when the download succeeds. If you see an error (e.g. `404 Not Found` or a network timeout), verify that the Unraid server has internet access and retry the command.

After a successful download the icon will appear automatically — no reboot required.

## Recommended initial settings

- `MEMORY_MB=2048` (increase to 3072/4096 if host allows)
- `PI_MODEL=pi4`

## Notes

- First boot is slow due to image download/extraction and guest initialization.
- If automatic image discovery fails, set `ZYNTHIAN_IMAGE_URL` in template variables.

#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"
DISK_SIZE_GB="${DISK_SIZE_GB:-16}"
EMULATION_STUBS="${EMULATION_STUBS:-0}"
DEFAULT_PUID=99
DEFAULT_PGID=100

mkdir -p "${DOWNLOAD_DIR}" "${BOOT_DIR}" "${DATA_DIR}"

is_positive_integer() {
  [[ "${1}" =~ ^[1-9][0-9]*$ ]]
}

is_power_of_two() {
  local value="${1}"
  (( value > 0 && (value & (value - 1)) == 0 ))
}

pick_owner_ids() {
  local detected_uid detected_gid
  detected_uid="$(stat -c '%u' "${DATA_DIR}" 2>/dev/null || echo 0)"
  detected_gid="$(stat -c '%g' "${DATA_DIR}" 2>/dev/null || echo 0)"

  if [[ -z "${PUID:-}" ]]; then
    if is_positive_integer "${detected_uid}" && [[ "${detected_uid}" != "0" ]]; then
      PUID="${detected_uid}"
    else
      PUID="${DEFAULT_PUID}"
    fi
  fi

  if [[ -z "${PGID:-}" ]]; then
    if is_positive_integer "${detected_gid}" && [[ "${detected_gid}" != "0" ]]; then
      PGID="${detected_gid}"
    else
      PGID="${DEFAULT_PGID}"
    fi
  fi
}

image_virtual_size_bytes() {
  qemu-img info -f raw "${1}" | awk -F'[()]' '/virtual size:/ {gsub(/ bytes/, "", $2); print $2; exit}'
}

partition_start_sector() {
  local image_path="${1}"
  local part_num="${2}"
  sfdisk -d "${image_path}" 2>/dev/null \
    | awk -v img="${image_path}" -v part="${part_num}" '
      $1 == img part {
        for (i = 1; i <= NF; i++) {
          if ($i == "start=") {
            v = $(i + 1)
            gsub(/,/, "", v)
            print v
            exit
          }
        }
      }
    '
}

apply_emulation_stubs() {
  local root_start_sector root_offset root_mount

  if [[ "${EMULATION_STUBS}" != "1" ]]; then
    return 0
  fi

  root_start_sector="$(partition_start_sector "${IMAGE_PATH}" 2)"
  if [[ -z "${root_start_sector}" ]]; then
    echo "WARNING: Could not detect root partition start sector for emulation stubs." >&2
    return 0
  fi

  root_offset="$((root_start_sector * 512))"
  root_mount="$(mktemp -d)"

  if ! mount -o "loop,rw,offset=${root_offset}" "${IMAGE_PATH}" "${root_mount}" 2>/dev/null; then
    echo "WARNING: Could not mount root partition to install emulation stubs." >&2
    rmdir "${root_mount}" 2>/dev/null || true
    return 0
  fi

  mkdir -p "${root_mount}/usr/local/sbin" \
           "${root_mount}/etc/systemd/system/multi-user.target.wants"

  cat > "${root_mount}/usr/local/sbin/dockerzynthian-emulation-stubs.sh" <<'EOF'
#!/bin/sh
set -eu

if [ -e /dev/i2c-1 ] || [ -e /dev/i2c/1 ]; then
  exit 0
fi

mkdir -p /dev/i2c
if [ ! -e /dev/i2c-1 ]; then
  mknod /dev/i2c-1 c 89 1 2>/dev/null || true
fi
if [ ! -e /dev/i2c/1 ]; then
  ln -sf /dev/i2c-1 /dev/i2c/1 || true
fi

if [ -x /usr/sbin/i2cdetect ] && [ ! -f /usr/sbin/i2cdetect.real ]; then
  mv /usr/sbin/i2cdetect /usr/sbin/i2cdetect.real
fi

cat > /usr/sbin/i2cdetect <<'STUB'
#!/bin/sh
echo "     0 1 2 3 4 5 6 7 8 9 a b c d e f"
for row in 00 10 20 30 40 50 60 70; do
  echo "${row}: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --"
done
exit 0
STUB
chmod +x /usr/sbin/i2cdetect
EOF

  chmod +x "${root_mount}/usr/local/sbin/dockerzynthian-emulation-stubs.sh"

  cat > "${root_mount}/etc/systemd/system/dockerzynthian-emulation-stubs.service" <<'EOF'
[Unit]
Description=DockerZynthian emulation hardware stubs
After=local-fs.target
Before=multi-user.target
ConditionPathExists=/usr/local/sbin/dockerzynthian-emulation-stubs.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/dockerzynthian-emulation-stubs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  ln -sf ../dockerzynthian-emulation-stubs.service \
    "${root_mount}/etc/systemd/system/multi-user.target.wants/dockerzynthian-emulation-stubs.service"

  sync
  umount "${root_mount}" 2>/dev/null || true
  rmdir "${root_mount}" 2>/dev/null || true
  echo "Installed emulation stubs in guest image (EMULATION_STUBS=1)."
}

find_existing_archive() {
  local archive
  archive="$(ls -1t \
    "${DOWNLOAD_DIR}"/*.img "${DOWNLOAD_DIR}"/*.img.xz "${DOWNLOAD_DIR}"/*.xz "${DOWNLOAD_DIR}"/*.zip "${DOWNLOAD_DIR}"/*.gz \
    "${DATA_DIR}"/*.img "${DATA_DIR}"/*.img.xz "${DATA_DIR}"/*.xz "${DATA_DIR}"/*.zip "${DATA_DIR}"/*.gz \
    2>/dev/null | head -n1 || true)"
  if [[ -n "${archive}" && -f "${archive}" ]]; then
    printf '%s' "${archive}"
    return 0
  fi
  return 1
}

if ! is_positive_integer "${DISK_SIZE_GB}" || ! is_power_of_two "${DISK_SIZE_GB}"; then
  echo "DISK_SIZE_GB must be a positive power-of-two integer (for example: 8, 16, 32)." >&2
  exit 1
fi

ARCHIVE_PATH="${1:-}"
CREATED_IMAGE=0

if [[ ! -f "${IMAGE_PATH}" ]]; then
  if [[ -z "${ARCHIVE_PATH}" ]]; then
    ARCHIVE_PATH="$(find_existing_archive || true)"
  fi
  if [[ -z "${ARCHIVE_PATH}" ]]; then
    ARCHIVE_PATH="$(/usr/local/bin/download-zynthian-image.sh)"
  fi
  if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    echo "Downloaded archive path is missing: ${ARCHIVE_PATH}" >&2
    exit 1
  fi
fi

TMP_IMG="${DATA_DIR}/extracted.img"

if [[ ! -f "${IMAGE_PATH}" ]]; then
  case "${ARCHIVE_PATH}" in
    *.img)
      cp -f "${ARCHIVE_PATH}" "${TMP_IMG}"
      ;;
    *.img.xz|*.xz)
      xz -dc "${ARCHIVE_PATH}" > "${TMP_IMG}"
      ;;
    *.img.gz|*.gz)
      gzip -dc "${ARCHIVE_PATH}" > "${TMP_IMG}"
      ;;
    *.zip)
      ZIP_IMG_ENTRY="$(unzip -Z1 "${ARCHIVE_PATH}" '*.img' | head -n1 || true)"
      if [[ -z "${ZIP_IMG_ENTRY}" ]]; then
        echo "Zip archive does not contain an .img file: ${ARCHIVE_PATH}" >&2
        exit 1
      fi
      unzip -p "${ARCHIVE_PATH}" "${ZIP_IMG_ENTRY}" > "${TMP_IMG}"
      ;;
    *)
      echo "Unsupported archive format: ${ARCHIVE_PATH}" >&2
      exit 1
      ;;
  esac
  if [[ ! -s "${TMP_IMG}" ]]; then
    echo "Image extraction failed for ${ARCHIVE_PATH}" >&2
    exit 1
  fi
  EXTRACTED_SIZE_BYTES="$(image_virtual_size_bytes "${TMP_IMG}")"
  mv -f "${TMP_IMG}" "${IMAGE_PATH}"
  CREATED_IMAGE=1
else
  if [[ -n "${ARCHIVE_PATH}" ]]; then
    echo "Using existing persistent image at ${IMAGE_PATH}; archive extraction skipped."
  fi
fi

CURRENT_SIZE_BYTES="$(image_virtual_size_bytes "${IMAGE_PATH}")"
TARGET_SIZE_BYTES="$((DISK_SIZE_GB * 1024 * 1024 * 1024))"
if (( CURRENT_SIZE_BYTES < TARGET_SIZE_BYTES )); then
  qemu-img resize -f raw "${IMAGE_PATH}" "${DISK_SIZE_GB}G" >/dev/null
elif (( CURRENT_SIZE_BYTES > TARGET_SIZE_BYTES )); then
  echo "WARNING: ${IMAGE_PATH} is already larger than ${DISK_SIZE_GB}G; keeping current size." >&2
fi
FINAL_SIZE_BYTES="$(image_virtual_size_bytes "${IMAGE_PATH}")"

if [[ "${CREATED_IMAGE}" -eq 0 ]]; then
  EXTRACTED_SIZE_BYTES="${FINAL_SIZE_BYTES}"
fi

START_SECTOR="$(partition_start_sector "${IMAGE_PATH}" 1)"
if [[ -z "${START_SECTOR}" ]]; then
  START_SECTOR="$(fdisk -l "${IMAGE_PATH}" | awk -v img="${IMAGE_PATH}" 'BEGIN { pattern = "^" img "[0-9]+$" } $1 ~ pattern && $2 ~ /^[0-9]+$/ {print $2; exit }')"
fi
if [[ -z "${START_SECTOR}" ]]; then
  echo "Could not detect boot partition sector offset." >&2
  exit 1
fi

OFFSET="$((START_SECTOR * 512))"
rm -f "${BOOT_DIR}"/kernel*.img "${BOOT_DIR}"/*.dtb

# Extract relevant boot files for raspi3/raspi4 QEMU boot
mcopy -n -i "${IMAGE_PATH}@@${OFFSET}" ::kernel*.img "${BOOT_DIR}/"
mcopy -n -i "${IMAGE_PATH}@@${OFFSET}" ::*.dtb "${BOOT_DIR}/"

if [[ ! -f "${BOOT_DIR}/kernel8.img" ]]; then
  echo "kernel8.img not found in boot partition extraction." >&2
  exit 1
fi

apply_emulation_stubs
pick_owner_ids
chown -R "${PUID}:${PGID}" "${DATA_DIR}" 2>/dev/null || true

echo "Downloaded archive path: ${ARCHIVE_PATH:-<existing image reused>}"
echo "Extracted raw size: ${EXTRACTED_SIZE_BYTES} bytes"
echo "Resized final size: ${FINAL_SIZE_BYTES} bytes (${DISK_SIZE_GB}G target)"
qemu-img info -f raw "${IMAGE_PATH}"
echo "Prepared image: ${IMAGE_PATH}"
echo "Boot files in: ${BOOT_DIR}"
echo "Ownership fixed to: ${PUID}:${PGID}"

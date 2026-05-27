#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"

mkdir -p "${DOWNLOAD_DIR}" "${BOOT_DIR}" "${DATA_DIR}"

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

ARCHIVE_PATH="${1:-}"
if [[ -z "${ARCHIVE_PATH}" ]]; then
  ARCHIVE_PATH="$(find_existing_archive || true)"
fi

if [[ -z "${ARCHIVE_PATH}" || ! -f "${ARCHIVE_PATH}" ]]; then
  echo "No downloaded archive found. Run download-zynthian-image.sh first." >&2
  exit 1
fi

TMP_IMG="${DATA_DIR}/extracted.img"

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

if [[ ! -f "${IMAGE_PATH}" ]]; then
  mv -f "${TMP_IMG}" "${IMAGE_PATH}"
else
  rm -f "${TMP_IMG}"
  echo "Persistent image already exists at ${IMAGE_PATH}; keeping existing disk state."
fi

if [[ -n "${DISK_EXPAND_GB:-}" ]]; then
  if [[ ! "${DISK_EXPAND_GB}" =~ ^[1-9][0-9]{0,2}$ ]]; then
    echo "DISK_EXPAND_GB must be a positive integer between 1 and 999." >&2
    exit 1
  fi
  qemu-img resize "${IMAGE_PATH}" "+${DISK_EXPAND_GB}G"
fi

# Prefer sfdisk dump parsing for consistent "start=" extraction from partition 1.
# sfdisk dump example: "<image>1 : start= 8192, ..."; extract first partition start sector.
START_SECTOR="$(sfdisk -d "${IMAGE_PATH}" 2>/dev/null | sed -nE 's/.*start= *([0-9]+).*/\1/p' | head -n1)"
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

echo "Prepared image: ${IMAGE_PATH}"
echo "Boot files in: ${BOOT_DIR}"

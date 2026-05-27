#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"

mkdir -p "${DOWNLOAD_DIR}" "${BOOT_DIR}" "${DATA_DIR}"

ARCHIVE_PATH="${1:-}"
if [[ -z "${ARCHIVE_PATH}" ]]; then
  ARCHIVE_PATH="$(ls -1t "${DOWNLOAD_DIR}"/* 2>/dev/null | head -n1 || true)"
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
    unzip -p "${ARCHIVE_PATH}" '*.img' > "${TMP_IMG}"
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
  qemu-img resize "${IMAGE_PATH}" "+${DISK_EXPAND_GB}G"
fi

START_SECTOR="$(fdisk -l "${IMAGE_PATH}" | awk '$1 ~ /[0-9]+$/ && $2 ~ /^[0-9]+$/ {print $2; exit}')"
if [[ -z "${START_SECTOR}" ]]; then
  echo "Could not detect boot partition sector offset." >&2
  exit 1
fi

OFFSET="$((START_SECTOR * 512))"
rm -f "${BOOT_DIR}"/kernel*.img "${BOOT_DIR}"/*.dtb

# Extract relevant boot files for raspi3/raspi4 QEMU boot
mcopy -n -i "${IMAGE_PATH}@@${OFFSET}" ::kernel*.img "${BOOT_DIR}/" || true
mcopy -n -i "${IMAGE_PATH}@@${OFFSET}" ::*.dtb "${BOOT_DIR}/" || true

if [[ ! -f "${BOOT_DIR}/kernel8.img" ]]; then
  echo "kernel8.img not found in boot partition extraction." >&2
  exit 1
fi

echo "Prepared image: ${IMAGE_PATH}"
echo "Boot files in: ${BOOT_DIR}"

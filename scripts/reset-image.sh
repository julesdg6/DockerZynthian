#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"

REMOVE_ALL=0
if [[ "${1:-}" == "--all" ]]; then
  REMOVE_ALL=1
fi

rm -f "${IMAGE_PATH}"
rm -rf "${BOOT_DIR}"

if [[ "${REMOVE_ALL}" -eq 1 ]]; then
  rm -rf "${DOWNLOAD_DIR}"
  echo "Removed image, bootfiles, and downloads cache."
else
  echo "Removed image and bootfiles."
  echo "Downloads kept at: ${DOWNLOAD_DIR} (use --all to remove them)."
fi

#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
DISK_SIZE_GB="${DISK_SIZE_GB:-16}"

if [[ ! "${DISK_SIZE_GB}" =~ ^[1-9][0-9]*$ ]]; then
  echo "DISK_SIZE_GB must be a positive integer." >&2
  exit 1
fi

if (( (DISK_SIZE_GB & (DISK_SIZE_GB - 1)) != 0 )); then
  echo "DISK_SIZE_GB must be a power of two (8, 16, 32, ...)." >&2
  exit 1
fi

if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "Image not found: ${IMAGE_PATH}" >&2
  exit 1
fi

echo "Resizing ${IMAGE_PATH} to ${DISK_SIZE_GB}G"
qemu-img resize -f raw "${IMAGE_PATH}" "${DISK_SIZE_GB}G"
echo "Resize complete."
qemu-img info -f raw "${IMAGE_PATH}"

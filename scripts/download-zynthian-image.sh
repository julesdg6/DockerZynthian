#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
mkdir -p "${DOWNLOAD_DIR}"

find_latest_url() {
  local index latest
  if ! index="$(curl -fsSL "https://os.zynthian.org/")"; then
    echo "Failed to fetch https://os.zynthian.org/ for automatic image discovery." >&2
    return 1
  fi
  # Expected index format: links including "stable"/"zynthian" and archive suffixes:
  # .img.xz, .img.gz, .xz, .gz, .img.zip, or .zip.
  latest="$(printf '%s' "${index}" \
    | grep -Eo 'href="[^"]*(stable|zynthian)[^"]*\.((img\.)?(xz|gz)|img\.zip|zip)"' \
    | sed -E 's/^href="([^"]+)"$/\1/' \
    | tail -n 1)"
  if [[ -n "${latest}" && "${latest}" != http* ]]; then
    latest="${latest#/}"
    latest="https://os.zynthian.org/${latest}"
  fi
  printf '%s' "${latest}"
}

IMAGE_URL="${ZYNTHIAN_IMAGE_URL:-}"
if [[ -z "${IMAGE_URL}" ]]; then
  IMAGE_URL="$(find_latest_url || true)"
fi

if [[ -z "${IMAGE_URL}" ]]; then
  echo "Could not automatically discover a stable official image URL from https://os.zynthian.org/." >&2
  echo "Set ZYNTHIAN_IMAGE_URL explicitly and re-run." >&2
  exit 1
fi

ARCHIVE_NAME="${IMAGE_URL##*/}"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE_NAME}"

if [[ -f "${ARCHIVE_PATH}" ]]; then
  echo "Using existing archive: ${ARCHIVE_PATH}"
else
  echo "Downloading: ${IMAGE_URL}"
  curl -fL --retry 3 --retry-delay 2 -o "${ARCHIVE_PATH}" "${IMAGE_URL}"
fi

echo "${ARCHIVE_PATH}"

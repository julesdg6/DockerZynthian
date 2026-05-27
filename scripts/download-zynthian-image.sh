#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
mkdir -p "${DOWNLOAD_DIR}"

find_latest_url() {
  local index latest
  index="$(curl -fsSL "https://os.zynthian.org/" || true)"
  latest="$(printf '%s' "${index}" \
    | grep -Eo 'href="[^"]*(stable|zynthian)[^"]*\.(img\.(xz|gz)|zip)"' \
    | sed -E 's/^href="([^"]+)"$/\1/' \
    | sed -E 's#^/#https://os.zynthian.org/#; s#^https?://#&#; t; s#^#https://os.zynthian.org/#' \
    | tail -n 1)"
  printf '%s' "${latest}"
}

IMAGE_URL="${ZYNTHIAN_IMAGE_URL:-}"
if [[ -z "${IMAGE_URL}" ]]; then
  IMAGE_URL="$(find_latest_url)"
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

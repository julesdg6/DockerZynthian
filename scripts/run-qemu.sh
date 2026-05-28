#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"

MEMORY_MB="${MEMORY_MB:-2048}"
PI_MODEL="${PI_MODEL:-pi4}"

SSH_PORT="${SSH_PORT:-2222}"
WEBCONF_PORT="${WEBCONF_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"
QEMU_SSH_PORT=2222
QEMU_WEBCONF_PORT=8080
QEMU_HTTPS_PORT=8443
QEMU_NOVNC_PORT=6080
QEMU_VNC_PORT=5900

mkdir -p "${DATA_DIR}" "${DOWNLOAD_DIR}" "${BOOT_DIR}"

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

if [[ ! -f "${IMAGE_PATH}" ]]; then
  ARCHIVE_PATH="$(find_existing_archive || true)"
  if [[ -z "${ARCHIVE_PATH}" ]]; then
    ARCHIVE_PATH="$(/usr/local/bin/download-zynthian-image.sh)"
  fi
  /usr/local/bin/prepare-image.sh "${ARCHIVE_PATH}"
elif [[ ! -f "${BOOT_DIR}/kernel8.img" ]]; then
  if ! /usr/local/bin/prepare-image.sh; then
    ARCHIVE_PATH="$(find_existing_archive || true)"
    if [[ -z "${ARCHIVE_PATH}" ]]; then
      ARCHIVE_PATH="$(/usr/local/bin/download-zynthian-image.sh)"
    fi
    /usr/local/bin/prepare-image.sh "${ARCHIVE_PATH}"
  fi
fi

KERNEL="${BOOT_DIR}/kernel8.img"
MACHINE="raspi4b"
CPU="cortex-a72"
DTB_CANDIDATES=("${BOOT_DIR}/bcm2711-rpi-4-b.dtb" "${BOOT_DIR}/bcm2711-rpi-400.dtb")

case "${PI_MODEL}" in
  pi3)
    MACHINE="raspi3b"
    CPU="cortex-a53"
    DTB_CANDIDATES=("${BOOT_DIR}/bcm2710-rpi-3-b-plus.dtb" "${BOOT_DIR}/bcm2710-rpi-3-b.dtb")
    ;;
  pi4)
    ;;
  pi5)
    echo "PI_MODEL=pi5 is not validated in this project. Falling back to pi4 emulation." >&2
    ;;
  *)
    echo "Unsupported PI_MODEL=${PI_MODEL}. Use pi3, pi4, or pi5 (fallback)." >&2
    exit 1
    ;;
esac

# Detect if the preferred QEMU machine is supported; automatically fall back if not.
if [[ "${MACHINE}" == "raspi4b" ]]; then
  if ! qemu-system-aarch64 -machine help 2>&1 | grep -qw "raspi4b"; then
    echo "WARNING: raspi4b is not supported by this QEMU installation." >&2
    echo "WARNING: Falling back to raspi3b (degraded emulation: Pi 3 instead of Pi 4)." >&2
    echo "WARNING: For full Pi 4 emulation, install QEMU >= 6.2 with raspi4b support." >&2
    MACHINE="raspi3b"
    CPU="cortex-a53"
    DTB_CANDIDATES=("${BOOT_DIR}/bcm2710-rpi-3-b-plus.dtb" "${BOOT_DIR}/bcm2710-rpi-3-b.dtb")
  fi
fi

DTB=""
for candidate in "${DTB_CANDIDATES[@]}"; do
  if [[ -f "${candidate}" ]]; then
    DTB="${candidate}"
    break
  fi
done

if [[ -z "${DTB}" ]]; then
  echo "No matching DTB found for ${PI_MODEL} in ${BOOT_DIR}" >&2
  exit 1
fi

# QEMU forwards to fixed container ports; Docker/Compose controls host-side port publishing.
NETDEV="user,id=net0,hostfwd=tcp::${QEMU_SSH_PORT}-:22,hostfwd=tcp::${QEMU_WEBCONF_PORT}-:80,hostfwd=tcp::${QEMU_HTTPS_PORT}-:443,hostfwd=tcp::${QEMU_NOVNC_PORT}-:6080,hostfwd=tcp::${QEMU_VNC_PORT}-:5900"

echo "Booting official ZynthianOS image with QEMU (${PI_MODEL} -> ${MACHINE})"
echo "Image: ${IMAGE_PATH}"
echo "RAM: ${MEMORY_MB} MB"
echo "Container forwards: ${QEMU_SSH_PORT}->22 ${QEMU_WEBCONF_PORT}->80 ${QEMU_HTTPS_PORT}->443 ${QEMU_NOVNC_PORT}->6080 ${QEMU_VNC_PORT}->5900"
echo "Published host ports: SSH:${SSH_PORT} WEB:${WEBCONF_PORT} HTTPS:${HTTPS_PORT} noVNC:${NOVNC_PORT} VNC:${VNC_PORT}"

exec qemu-system-aarch64 \
  -machine "${MACHINE}" \
  -cpu "${CPU}" \
  -m "${MEMORY_MB}" \
  -smp 4 \
  -kernel "${KERNEL}" \
  -dtb "${DTB}" \
  -drive "if=sd,format=raw,file=${IMAGE_PATH}" \
  -append "rw root=/dev/mmcblk0p2 rootwait fsck.repair=yes console=ttyAMA0,115200 console=tty1" \
  -netdev "${NETDEV}" \
  -device usb-net,netdev=net0 \
  -nographic

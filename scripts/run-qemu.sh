#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${DATA_DIR}/downloads}"
IMAGE_PATH="${IMAGE_PATH:-${DATA_DIR}/zynthian.img}"
BOOT_DIR="${BOOT_DIR:-${DATA_DIR}/bootfiles}"

MEMORY_MB="${MEMORY_MB:-1024}"
PI_MODEL="${PI_MODEL:-pi3}"
DISK_SIZE_GB="${DISK_SIZE_GB:-16}"
EMULATION_STUBS="${EMULATION_STUBS:-0}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
DISPLAY_MODE="${DISPLAY_MODE:-none}"
ENABLE_FAKE_DISPLAY="${ENABLE_FAKE_DISPLAY:-0}"

SSH_PORT="${SSH_PORT:-2222}"
WEBCONF_PORT="${WEBCONF_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"
DISPLAY_VNC_PORT="${DISPLAY_VNC_PORT:-5901}"
QEMU_SSH_PORT=2222
QEMU_WEBCONF_PORT=8080
QEMU_HTTPS_PORT=8443
QEMU_NOVNC_PORT=6080
QEMU_VNC_PORT=5900
QEMU_DISPLAY_VNC_PORT=5901

mkdir -p "${DATA_DIR}" "${DOWNLOAD_DIR}" "${BOOT_DIR}"

is_supported_machine() {
  local machine="${1}"
  printf '%s\n' "${SUPPORTED_MACHINES}" | grep -qw "${machine}"
}

machine_cpu() {
  case "${1}" in
    raspi4b) printf 'cortex-a72' ;;
    raspi3b|raspi3ap) printf 'cortex-a53' ;;
    *) printf 'cortex-a53' ;;
  esac
}

machine_dtb_candidates() {
  case "${1}" in
    raspi4b)
      printf '%s\n' "${BOOT_DIR}/bcm2711-rpi-4-b.dtb" "${BOOT_DIR}/bcm2711-rpi-400.dtb"
      ;;
    raspi3b)
      printf '%s\n' "${BOOT_DIR}/bcm2710-rpi-3-b-plus.dtb" "${BOOT_DIR}/bcm2710-rpi-3-b.dtb"
      ;;
    raspi3ap)
      printf '%s\n' "${BOOT_DIR}/bcm2710-rpi-3-a-plus.dtb" "${BOOT_DIR}/bcm2710-rpi-3-b-plus.dtb"
      ;;
    *)
      return 1
      ;;
  esac
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

if [[ ! -f "${IMAGE_PATH}" || ! -f "${BOOT_DIR}/kernel8.img" ]]; then
  ARCHIVE_PATH="$(find_existing_archive || true)"
  if [[ -n "${ARCHIVE_PATH}" ]]; then
    /usr/local/bin/prepare-image.sh "${ARCHIVE_PATH}"
  else
    /usr/local/bin/prepare-image.sh
  fi
fi

KERNEL="${BOOT_DIR}/kernel8.img"
case "${PI_MODEL}" in
  pi3)
    REQUESTED_MACHINE="raspi3b"
    ;;
  pi4)
    REQUESTED_MACHINE="raspi4b"
    ;;
  pi5)
    echo "PI_MODEL=pi5 is not validated in this project. Falling back to pi4 emulation." >&2
    REQUESTED_MACHINE="raspi4b"
    ;;
  *)
    echo "Unsupported PI_MODEL=${PI_MODEL}. Use pi3, pi4, or pi5 (fallback)." >&2
    exit 1
    ;;
esac

if ! [[ "${MEMORY_MB}" =~ ^[1-9][0-9]*$ ]]; then
  echo "MEMORY_MB must be a positive integer." >&2
  exit 1
fi

SUPPORTED_MACHINES="$("${QEMU_BIN}" -machine help 2>/dev/null || true)"

if [[ -z "${SUPPORTED_MACHINES}" ]]; then
  echo "Unable to query supported machines from ${QEMU_BIN}." >&2
  exit 1
fi

FALLBACK_ORDER=(raspi4b raspi3b raspi3ap)
if is_supported_machine "${REQUESTED_MACHINE}"; then
  MACHINE="${REQUESTED_MACHINE}"
else
  MACHINE=""
  for candidate in "${FALLBACK_ORDER[@]}"; do
    if is_supported_machine "${candidate}"; then
      MACHINE="${candidate}"
      break
    fi
  done
  if [[ -z "${MACHINE}" ]]; then
    echo "No supported Raspberry Pi machine found in this QEMU build." >&2
    exit 1
  fi
  echo "WARNING: ${REQUESTED_MACHINE} is not supported by this QEMU build. Falling back to ${MACHINE}." >&2
fi

if [[ "${MACHINE}" == "raspi3b" || "${MACHINE}" == "raspi3ap" ]]; then
  if [[ "${MEMORY_MB}" != "1024" ]]; then
    echo "WARNING: ${MACHINE} only supports 1024MB RAM in QEMU. Clamping MEMORY_MB to 1024." >&2
  fi
  MEMORY_MB=1024
fi

CPU="$(machine_cpu "${MACHINE}")"
mapfile -t DTB_CANDIDATES < <(machine_dtb_candidates "${MACHINE}")

DTB=""
for candidate in "${DTB_CANDIDATES[@]}"; do
  if [[ -f "${candidate}" ]]; then
    DTB="${candidate}"
    break
  fi
done

if [[ -z "${DTB}" ]]; then
  echo "No matching DTB found for ${MACHINE} in ${BOOT_DIR}" >&2
  exit 1
fi

# QEMU forwards to fixed container ports; Docker/Compose controls host-side port publishing.
NETDEV="user,id=net0,hostfwd=tcp::${QEMU_SSH_PORT}-:22,hostfwd=tcp::${QEMU_WEBCONF_PORT}-:80,hostfwd=tcp::${QEMU_HTTPS_PORT}-:443,hostfwd=tcp::${QEMU_NOVNC_PORT}-:6080,hostfwd=tcp::${QEMU_VNC_PORT}-:5900"

IMAGE_VIRTUAL_SIZE="$(qemu-img info -f raw "${IMAGE_PATH}" | awk -F'[()]' '/virtual size:/ {gsub(/ bytes/, "", $2); print $2; exit}')"

KERNEL_CMDLINE="rw root=/dev/mmcblk0p2 rootwait fsck.repair=yes console=ttyAMA0,115200 console=tty1 loglevel=7"
if [[ "${ENABLE_FAKE_DISPLAY}" == "1" ]]; then
  KERNEL_CMDLINE="${KERNEL_CMDLINE} drm_kms_helper.fbdev_emulation=1"
fi

# Build QEMU display flags.
# DISPLAY_MODE=none  : headless (-nographic); no QEMU display VNC server.
# DISPLAY_MODE=vnc   : QEMU built-in VNC server on container port 5901 (VNC display :1).
#                      NOTE: raspi machines have no emulated GPU, so the VNC image will be
#                      blank/black.  This is still useful for debug and may help guest
#                      framebuffer detection in some kernel configurations.
# DISPLAY_MODE=gtk   : GTK window; only usable when a host DISPLAY is forwarded into
#                      the container (e.g. via X11 socket bind-mount).
DISPLAY_QEMU_FLAGS=()
case "${DISPLAY_MODE}" in
  none)
    DISPLAY_QEMU_FLAGS=(-nographic)
    ;;
  vnc)
    DISPLAY_QEMU_FLAGS=(-display "vnc=0.0.0.0:1" -serial mon:stdio)
    ;;
  gtk)
    DISPLAY_QEMU_FLAGS=(-display gtk -serial mon:stdio)
    ;;
  *)
    echo "Unsupported DISPLAY_MODE=${DISPLAY_MODE}. Use none, vnc, or gtk." >&2
    exit 1
    ;;
esac

echo "Booting official ZynthianOS image with QEMU (${PI_MODEL} -> ${MACHINE})"
echo "QEMU binary: ${QEMU_BIN}"
echo "Selected machine type: ${MACHINE}"
echo "Image: ${IMAGE_PATH}"
echo "Image virtual size: ${IMAGE_VIRTUAL_SIZE} bytes"
echo "DISK_SIZE_GB target: ${DISK_SIZE_GB}"
echo "EMULATION_STUBS: ${EMULATION_STUBS}"
echo "DISPLAY_MODE: ${DISPLAY_MODE}"
echo "ENABLE_FAKE_DISPLAY: ${ENABLE_FAKE_DISPLAY}"
echo "RAM: ${MEMORY_MB} MB"
echo "Container forwards: ${QEMU_SSH_PORT}->22 ${QEMU_WEBCONF_PORT}->80 ${QEMU_HTTPS_PORT}->443 ${QEMU_NOVNC_PORT}->6080 ${QEMU_VNC_PORT}->5900"
echo "Published host ports: SSH:${SSH_PORT} WEB:${WEBCONF_PORT} HTTPS:${HTTPS_PORT} noVNC:${NOVNC_PORT} VNC:${VNC_PORT}"
if [[ "${DISPLAY_MODE}" == "vnc" ]]; then
  echo "QEMU display VNC: container port ${QEMU_DISPLAY_VNC_PORT} -> host port ${DISPLAY_VNC_PORT}"
  echo "  Connect to QEMU display: VNC viewer to HOST:${DISPLAY_VNC_PORT}"
fi
echo "Expected access:"
echo "  SSH: ssh -p ${SSH_PORT} root@HOST"
echo "  Webconf: http://HOST:${WEBCONF_PORT}"
echo "  HTTPS: https://HOST:${HTTPS_PORT}"
echo "  noVNC: http://HOST:${NOVNC_PORT}"
echo "Note: usbnet control transaction noise may appear while boot continues."

exec "${QEMU_BIN}" \
  -machine "${MACHINE}" \
  -cpu "${CPU}" \
  -m "${MEMORY_MB}" \
  -smp 4 \
  -kernel "${KERNEL}" \
  -dtb "${DTB}" \
  -drive "if=sd,format=raw,file=${IMAGE_PATH}" \
  -append "${KERNEL_CMDLINE}" \
  -netdev "${NETDEV}" \
  -device usb-net,netdev=net0 \
  "${DISPLAY_QEMU_FLAGS[@]}"

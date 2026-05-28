#!/usr/bin/env bash
set -euo pipefail

QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
SUPPORTED="$("${QEMU_BIN}" -machine help 2>/dev/null || true)"

if [[ -z "${SUPPORTED}" ]]; then
  echo "Unable to query machine support from ${QEMU_BIN}." >&2
  exit 1
fi

echo "QEMU binary: ${QEMU_BIN}"
echo "Supported Raspberry Pi machines:"
FOUND=0
for machine in raspi4b raspi3b raspi3ap; do
  if printf '%s\n' "${SUPPORTED}" | grep -qw "${machine}"; then
    echo "  - ${machine}"
    FOUND=1
  fi
done

if [[ "${FOUND}" -eq 0 ]]; then
  echo "  (none of raspi4b/raspi3b/raspi3ap found)"
  exit 1
fi

if printf '%s\n' "${SUPPORTED}" | grep -qw "raspi4b"; then
  echo "Recommended PI_MODEL=pi4"
elif printf '%s\n' "${SUPPORTED}" | grep -qw "raspi3b"; then
  echo "Recommended PI_MODEL=pi3"
else
  echo "Recommended PI_MODEL=pi3 (raspi3ap fallback)"
fi

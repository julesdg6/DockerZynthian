# USB passthrough (audio + MIDI)

DockerZynthian focuses first on network reachability (Webconf). USB passthrough is best-effort.

## Docker / Compose

Add:

- `privileged: true`
- device map `/dev/bus/usb:/dev/bus/usb`

Then inside QEMU, attach matching USB devices (future automation TODO).

## Unraid

- Keep container privileged.
- Map `/dev/bus/usb` into the container if needed.

## Limitations

- Device indexing can change after reboot/replug.
- Low-latency/hard real-time audio cannot be guaranteed under emulation.
- Some interfaces may require additional guest configuration.

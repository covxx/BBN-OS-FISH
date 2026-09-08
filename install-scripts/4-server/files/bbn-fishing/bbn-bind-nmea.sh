#!/bin/bash
# Bind a USB-serial device to /dev/ttyFISH or /dev/ttyWIND.
# Usage: bbn-bind-nmea fish /dev/ttyUSB0
#        bbn-bind-nmea wind /dev/ttyUSB1
# Optional third argument is baud (default 4800, Garmin-style). Use 38400 if needed.

set -euo pipefail

role="${1:-}"
dev="${2:-}"
baud="${3:-4800}"

if [[ "$role" != "fish" && "$role" != "wind" ]]; then
  echo "Usage: bbn-bind-nmea fish|wind /dev/ttyUSB0 [baud]" >&2
  exit 1
fi

if [[ ! -e "$dev" ]]; then
  echo "Device $dev does not exist" >&2
  exit 1
fi

eval "$(udevadm info -q property -n "$dev" | grep -E '^(ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT)=')"

if [[ -z "${ID_VENDOR_ID:-}" || -z "${ID_MODEL_ID:-}" ]]; then
  echo "Could not read USB vendor/product for $dev" >&2
  exit 1
fi

link="ttyFISH"
provider="fish_nmea"
rule="/etc/udev/rules.d/92-bbn-fish.rules"
if [[ "$role" == "wind" ]]; then
  link="ttyWIND"
  provider="wind_nmea"
  rule="/etc/udev/rules.d/92-bbn-wind.rules"
fi

serial_match=""
if [[ -n "${ID_SERIAL_SHORT:-}" ]]; then
  serial_match=", ATTRS{serial}==\"${ID_SERIAL_SHORT}\""
fi

cat > "$rule" <<EOF
SUBSYSTEM=="tty", ATTRS{idVendor}=="${ID_VENDOR_ID}", ATTRS{idProduct}=="${ID_MODEL_ID}"${serial_match}, SYMLINK+="${link}", MODE="0660", GROUP="dialout"
EOF

udevadm control --reload-rules
udevadm trigger --subsystem-match=tty || true
ln -sfn "$dev" "/dev/${link}" || true

settings="/home/signalk/.signalk/settings.json"
if [[ -f "$settings" ]] && command -v jq >/dev/null; then
  tmp=$(mktemp)
  jq --arg id "$provider" --argjson baud "$baud" '
    .pipedProviders |= map(
      if .id == $id then
        .enabled = true
        | .pipeElements[0].options.subOptions.baudrate = $baud
      else . end
    )' "$settings" > "$tmp"
  install -m 644 -o signalk -g signalk "$tmp" "$settings"
  rm -f "$tmp"
  echo "Enabled Signal K provider ${provider} at ${baud} baud. Restart Signal K to read the port."
else
  echo "Wrote ${rule}. Enable the ${provider} provider in Signal K and restart it."
fi

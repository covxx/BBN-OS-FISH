#!/bin/bash
# Start the bench NMEA source and enable the fish_sim Signal K provider.
# Depth dips under 4 ft on a cycle so the shallow banner can be checked.
# This is not a substitute for a fish finder. Stop with Ctrl-C.

set -euo pipefail

settings="/home/signalk/.signalk/settings.json"
if [[ -f "$settings" ]] && command -v jq >/dev/null; then
  tmp=$(mktemp)
  jq '
    .pipedProviders |= map(
      if .id == "fish_sim" then .enabled = true else . end
    )' "$settings" > "$tmp"
  if [[ "$(id -u)" -eq 0 ]]; then
    install -m 644 -o signalk -g signalk "$tmp" "$settings"
  else
    sudo install -m 644 -o signalk -g signalk "$tmp" "$settings"
  fi
  rm -f "$tmp"
fi

python3 /usr/local/share/bbn-fishing/bbn-nmea-sim.py &
sim_pid=$!
trap 'kill "$sim_pid" 2>/dev/null || true' EXIT

sleep 1
if [[ -x /usr/local/sbin/signalk-restart ]]; then
  /usr/local/sbin/signalk-restart || true
fi

echo "Bench NMEA is on 127.0.0.1:10117. Open the Fishing page."
wait "$sim_pid"

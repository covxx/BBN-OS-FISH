#!/bin/bash
# Convert a georeferenced image to a KAP chart and drop it in /srv/charts.
# Usage: bbn-chart-kap image.png north south east west [name]
# Latitudes and longitudes are decimal degrees. West longitudes are negative.

set -euo pipefail

image="${1:-}"
north="${2:-}"
south="${3:-}"
east="${4:-}"
west="${5:-}"
name="${6:-custom-chart}"

if [[ -z "$image" || -z "$north" || -z "$south" || -z "$east" || -z "$west" ]]; then
  echo "Usage: bbn-chart-kap image.png north south east west [name]" >&2
  exit 1
fi

if [[ ! -f "$image" ]]; then
  echo "Image not found: $image" >&2
  exit 1
fi

if ! command -v imgkap >/dev/null; then
  echo "imgkap is not installed. It is built with OpenCPN on the full image." >&2
  exit 1
fi

out="/srv/charts/${name}.kap"
imgkap -n "$north" -s "$south" -e "$east" -w "$west" "$image" "$out"
chgrp charts "$out" || true
chmod 664 "$out" || true
echo "Wrote $out"
echo "OpenCPN chart directory is /home/user/charts (same folder). Rebuild the chart database if the chart is not listed."

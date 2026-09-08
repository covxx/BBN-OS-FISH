#!/bin/bash
# Apply helm settings into Signal K. Called as root from the fishing service.
set -euo pipefail

src="${1:-}"
if [[ -z "$src" || ! -f "$src" ]]; then
  echo "usage: bbn-helm-apply settings.json" >&2
  exit 1
fi

python3 - "$src" <<'PY'
import json
import sys

src = sys.argv[1]
with open(src, encoding="utf-8") as handle:
    settings = json.load(handle)

ft = 3.280839895
offset_m = float(settings.get("transducerOffsetFt") or 0) / ft
draft_m = float(settings.get("draftFt") or 0) / ft
alarm_m = float(settings.get("shallowAlarmFt") or 4) / ft
alarm_on = bool(settings.get("shallowAlarmEnabled"))
ina_on = bool(settings.get("ina219Enabled"))
key = (settings.get("openweatherKey") or "").strip()

defaults_path = "/home/signalk/.signalk/defaults.json"
try:
    with open(defaults_path, encoding="utf-8") as handle:
        defaults = json.load(handle)
except (OSError, json.JSONDecodeError):
    defaults = {"vessels": {"self": {}}}
self = defaults.setdefault("vessels", {}).setdefault("self", {})
design = self.setdefault("design", {})
design["draft"] = {"maximum": round(draft_m, 3)}
self.setdefault("sensors", {}).setdefault("depth", {})["offset"] = round(offset_m, 3)
with open(defaults_path, "w", encoding="utf-8") as handle:
    json.dump(defaults, handle, indent=2)
    handle.write("\n")

notes_path = "/home/signalk/.signalk/plugin-config-data/simple-notifications.json"
try:
    with open(notes_path, encoding="utf-8") as handle:
        notes = json.load(handle)
except (OSError, json.JSONDecodeError):
    notes = {"enabled": True, "configuration": {"paths": []}}
for path in notes.get("configuration", {}).get("paths", []):
    if path.get("key") == "environment.depth.belowSurface":
        path["enabled"] = alarm_on
        path["lowValue"] = round(alarm_m, 4)
        path["name"] = "shallow water"
with open(notes_path, "w", encoding="utf-8") as handle:
    json.dump(notes, handle, indent=2)
    handle.write("\n")

ina_path = "/home/signalk/.signalk/plugin-config-data/signalk-raspberry-pi-ina219.json"
try:
    with open(ina_path, encoding="utf-8") as handle:
        ina = json.load(handle)
except (OSError, json.JSONDecodeError):
    ina = {"configuration": {"i2c_bus": 1, "i2c_address": "0x40", "battery": 0}}
ina["enabled"] = ina_on
with open(ina_path, "w", encoding="utf-8") as handle:
    json.dump(ina, handle, indent=2)
    handle.write("\n")

wx_path = "/home/signalk/.signalk/plugin-config-data/openweather-signalk.json"
try:
    with open(wx_path, encoding="utf-8") as handle:
        wx = json.load(handle)
except (OSError, json.JSONDecodeError):
    wx = {"configuration": {}}
wx["enabled"] = bool(key)
wx.setdefault("configuration", {})
wx["configuration"]["apikey"] = key
wx["configuration"]["apiKey"] = key
wx["configuration"]["interval"] = 60
wx["configuration"]["position"] = "signalk"
with open(wx_path, "w", encoding="utf-8") as handle:
    json.dump(wx, handle, indent=2)
    handle.write("\n")
PY

chown signalk:signalk /home/signalk/.signalk/defaults.json || true
chown signalk:signalk /home/signalk/.signalk/plugin-config-data/simple-notifications.json || true
chown signalk:signalk /home/signalk/.signalk/plugin-config-data/signalk-raspberry-pi-ina219.json || true
chown signalk:signalk /home/signalk/.signalk/plugin-config-data/openweather-signalk.json || true

if [[ -x /usr/local/sbin/signalk-restart ]]; then
  /usr/local/sbin/signalk-restart || true
fi

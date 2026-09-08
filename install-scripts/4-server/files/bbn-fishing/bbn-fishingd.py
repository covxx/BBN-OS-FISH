#!/usr/bin/env python3
"""Local fishing page and waypoint writer for the cockpit touch screen."""

import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
SETTINGS = os.path.expanduser("/home/user/.config/bbn-fishing/settings.json")
GPX_CHARTS = "/srv/charts/fishing-marks.gpx"
GPX_LAYER = os.path.expanduser("/home/user/.opencpn/layers/fishing-marks.gpx")
HOST = "127.0.0.1"
PORT = 8765


def load_settings():
    try:
        with open(SETTINGS, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        data = {}
    data.setdefault("shallowAlarmFt", 4)
    data.setdefault("shallowAlarmEnabled", False)
    data.setdefault("transducerOffsetFt", 0)
    data.setdefault("draftFt", 2)
    data.setdefault("openweatherKey", "")
    data.setdefault("ina219Enabled", False)
    return data


def save_settings(data):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def xml_escape(text):
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def read_gpx(path):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    marks = []
    start = 0
    while True:
        i = text.find("<wpt ", start)
        if i < 0:
            break
        j = text.find("</wpt>", i)
        if j < 0:
            break
        marks.append(text[i : j + 6])
        start = j + 6
    return marks


def write_gpx(path, marks):
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    body = "\n".join(marks)
    text = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="bbn-fishing" '
        'xmlns="http://www.topografix.com/GPX/1/1">\n'
        "<metadata><name>Fishing marks</name></metadata>\n"
        f"{body}\n"
        "</gpx>\n"
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def add_mark(payload):
    lat = float(payload["latitude"])
    lon = float(payload["longitude"])
    now = datetime.now(timezone.utc).replace(microsecond=0)
    stamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    name = "Fish " + now.strftime("%H%M")
    note = (payload.get("note") or "").strip()
    parts = [f"Marked {stamp}"]
    if payload.get("depthFt") is not None:
        parts.append(f"depth {payload['depthFt']} ft")
    if payload.get("tempF") is not None:
        parts.append(f"water {payload['tempF']} F")
    if note:
        parts.append(note)
    desc = xml_escape(". ".join(parts))
    mark = (
        f'<wpt lat="{lat:.6f}" lon="{lon:.6f}">'
        f"<time>{stamp}</time>"
        f"<name>{xml_escape(name)}</name>"
        f"<desc>{desc}</desc>"
        f"<sym>circle</sym>"
        f"</wpt>"
    )
    marks = read_gpx(GPX_CHARTS)
    marks.append(mark)
    write_gpx(GPX_CHARTS, marks)
    try:
        write_gpx(GPX_LAYER, marks)
    except OSError:
        pass
    return {"ok": True, "name": name}


FT = 3.280839895
KTS = 1.943844492
LOCK = threading.Lock()
RADAR_PATH = os.path.expanduser("/home/user/.config/bbn-fishing/radar.gif")
SEEN_ALERTS = os.path.expanduser("/home/user/.config/bbn-fishing/seen-alerts.json")
STATE = {
    "sk": "waiting",
    "fishConnected": False,
    "windConnected": False,
    "depthFt": None,
    "xdcrFt": None,
    "tempF": None,
    "depthFresh": False,
    "lat": None,
    "lon": None,
    "sogKn": None,
    "gpsFresh": False,
    "windMeasuredKn": None,
    "windLabel": "not connected",
    "pressureHpa": None,
    "baroFalling": False,
    "houseV": None,
    "houseA": None,
    "boatV": None,
    "solarW": None,
    "solarHint": "",
    "shallow": False,
    "weather": {"status": "waiting", "alerts": [], "forecast": [], "forecastWind": "", "radarMode": "none"},
    "network": {"modem": "no modem", "wifi": "not connected", "cellOnly": False},
}
PRESSURE = []
SOLAR_SEEN = False
LAST_ALERT_IDS = set()
LAST_NWS = 0
LAST_RADAR = 0


def device_up(path):
    return os.path.exists(path)


def sk_get(url):
    headers = {"User-Agent": "bbn-helm"}
    token_path = os.path.expanduser("/home/user/.config/bbn-fishing/sk-token")
    if os.path.isfile(token_path):
        headers["Authorization"] = "Bearer " + open(token_path, encoding="utf-8").read().strip()
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=4) as handle:
        return json.loads(handle.read().decode("utf-8"))


def walk_values(node, prefix, out, times):
    if not isinstance(node, dict):
        return
    if "value" in node and "timestamp" in node and not isinstance(node.get("value"), dict):
        out[prefix] = node.get("value")
        times[prefix] = node.get("timestamp")
        return
    for key, child in node.items():
        if key in ("meta", "$source"):
            continue
        nxt = f"{prefix}.{key}" if prefix else key
        walk_values(child, nxt, out, times)


def num_of(values, path):
    value = values.get(path)
    if isinstance(value, (int, float)):
        return float(value)
    return None


def fresh_ts(times, path, limit=20):
    stamp = times.get(path)
    if not stamp:
        return False
    try:
        then = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return False
    return time.time() - then < limit


def sound_alarm():
    for cmd in (
        ["canberra-gtk-play", "-i", "dialog-warning"],
        ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
    ):
        try:
            subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            return
        except (OSError, subprocess.TimeoutExpired):
            continue


def apply_settings(settings):
    apply = "/usr/local/sbin/bbn-helm-apply"
    if not os.path.isfile(apply):
        return
    try:
        subprocess.run(["sudo", "-n", apply, SETTINGS], check=False, timeout=40)
    except (OSError, subprocess.TimeoutExpired):
        pass


def fetch_nws(lat, lon):
    headers = {"User-Agent": "bbn-helm (local boat computer)", "Accept": "application/geo+json"}
    points_url = f"https://api.weather.gov/points/{lat:.4f},{lon:.4f}"
    req = urllib.request.Request(points_url, headers=headers)
    with urllib.request.urlopen(req, timeout=12) as handle:
        points = json.loads(handle.read().decode("utf-8"))
    props = points.get("properties") or {}
    forecast = []
    forecast_url = props.get("forecast")
    if forecast_url:
        req = urllib.request.Request(forecast_url, headers=headers)
        with urllib.request.urlopen(req, timeout=12) as handle:
            body = json.loads(handle.read().decode("utf-8"))
        for period in (body.get("properties") or {}).get("periods") or []:
            if len(forecast) >= 4:
                break
            forecast.append({
                "name": period.get("name") or "",
                "text": period.get("shortForecast") or "",
                "wind": f"{period.get('windSpeed') or ''} {period.get('windDirection') or ''}".strip(),
                "temp": period.get("temperature"),
                "unit": period.get("temperatureUnit") or "F",
            })
    alerts = []
    alert_url = f"https://api.weather.gov/alerts/active?point={lat:.4f},{lon:.4f}"
    req = urllib.request.Request(alert_url, headers=headers)
    with urllib.request.urlopen(req, timeout=12) as handle:
        body = json.loads(handle.read().decode("utf-8"))
    for feature in body.get("features") or []:
        prop = feature.get("properties") or {}
        alerts.append({
            "id": prop.get("id") or feature.get("id") or "",
            "event": prop.get("event") or "Alert",
            "severity": prop.get("severity") or "",
            "headline": prop.get("headline") or prop.get("event") or "Alert",
            "expires": prop.get("expires") or "",
        })
    return {
        "status": "live",
        "radarStation": props.get("radarStation") or "",
        "forecast": forecast,
        "forecastWind": forecast[0]["wind"] if forecast else "",
        "alerts": alerts,
    }


def read_modem():
    try:
        listing = subprocess.run(["mmcli", "-L"], capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return {"modem": "no modem", "wifi": "", "cellOnly": False, "up": False}
    modem_id = None
    for line in listing.stdout.splitlines():
        if "/Modem/" in line:
            modem_id = line.split("/Modem/")[-1].split()[0]
            break
    if not modem_id:
        return None
    try:
        info = subprocess.run(["mmcli", "-m", modem_id, "-J"], capture_output=True, text=True, timeout=8)
        data = json.loads(info.stdout or "{}")
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return {"present": True, "modem": "modem present", "tech": "", "dbm": None, "up": False}
    modem = (data.get("modem") or data)
    generic = modem.get("generic") or {}
    state = generic.get("state") or ""
    operator = ((modem.get("3gpp") or {}).get("operator-name")) or generic.get("manufacturer") or "USB modem"
    techs = generic.get("access-technologies") or []
    tech = techs[0] if techs else ""
    quality = generic.get("signal-quality") or {}
    value = quality.get("value")
    return {
        "present": True,
        "modem": operator,
        "tech": tech,
        "bars": value,
        "up": state in ("connected", "registered"),
        "state": state,
    }


def read_wifi():
    try:
        proc = subprocess.run(
            ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"],
            capture_output=True, text=True, timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {"name": "unknown", "cell": False, "wifi": False}
    wifi = ""
    cell = False
    for line in proc.stdout.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        name, kind, _dev, state = parts[0], parts[1], parts[2], parts[3]
        if state != "activated":
            continue
        if kind in ("802-11-wireless", "wifi"):
            wifi = name
        if kind in ("gsm", "cdma", "wwan"):
            cell = True
    return {"name": wifi or "not connected", "cell": cell, "wifi": bool(wifi)}


def collect_once():
    global SOLAR_SEEN, LAST_NWS, LAST_RADAR
    settings = load_settings()
    values = {}
    times = {}
    sk = "not connected"
    try:
        vessel = sk_get("http://127.0.0.1:3000/signalk/v1/api/vessels/self")
        walk_values(vessel, "", values, times)
        sk = "live"
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        sk = "Signal K not readable"

    offset_m = float(settings.get("transducerOffsetFt") or 0) / FT
    surface = num_of(values, "environment.depth.belowSurface")
    xdcr = num_of(values, "environment.depth.belowTransducer")
    if surface is None and xdcr is not None:
        surface = xdcr + offset_m
    depth_fresh = fresh_ts(times, "environment.depth.belowSurface") or fresh_ts(times, "environment.depth.belowTransducer")
    temp = num_of(values, "environment.water.temperature")
    if temp is None:
        temp = num_of(values, "environment.water.temperatureSurface")
    pos = values.get("navigation.position") or {}
    lat = pos.get("latitude") if isinstance(pos, dict) else None
    lon = pos.get("longitude") if isinstance(pos, dict) else None
    gps_fresh = fresh_ts(times, "navigation.position", 30) and isinstance(lat, (int, float))
    sog = num_of(values, "navigation.speedOverGround")
    measured = num_of(values, "environment.wind.speedApparent")
    if measured is None:
        measured = num_of(values, "environment.wind.speedTrue")
    pressure = num_of(values, "environment.outside.pressure")
    hpa = pressure / 100.0 if pressure and pressure > 2000 else pressure
    now = time.time()
    if hpa:
        PRESSURE.append((now, hpa))
    cutoff = now - 3 * 3600
    while PRESSURE and PRESSURE[0][0] < cutoff:
        PRESSURE.pop(0)
    falling = False
    if hpa and PRESSURE:
        oldest = PRESSURE[0][1]
        falling = oldest - hpa >= 3

    house_v = num_of(values, "electrical.batteries.0.voltage")
    house_a = num_of(values, "electrical.batteries.0.current")
    boat_v = num_of(values, "electrical.batteries.1.voltage")
    solar = num_of(values, "electrical.solar.0.panelPower")
    if solar is None:
        solar = num_of(values, "electrical.solar.0.power")
    if solar and solar > 5:
        SOLAR_SEEN = True
    hour = datetime.now().hour
    daylight = 7 <= hour <= 19
    solar_hint = ""
    if SOLAR_SEEN and daylight and (solar is None or solar < 1):
        solar_hint = "solar not charging"

    shallow = bool(settings.get("shallowAlarmEnabled") and depth_fresh and surface is not None and surface * FT < float(settings.get("shallowAlarmFt") or 4))
    fish_connected = device_up("/dev/ttyFISH")
    wind_connected = device_up("/dev/ttyWIND")

    modem = read_modem()
    wifi = read_wifi()
    cell_only = bool(modem and modem.get("up") and not wifi.get("wifi"))
    if modem is None:
        net_modem = "no modem"
    else:
        bars = modem.get("bars")
        bit = f"{modem.get('modem')} {modem.get('tech') or ''}".strip()
        if bars is not None:
            bit += f" {bars}%"
        bit += " data up" if modem.get("up") else " no data"
        net_modem = bit

    weather = dict(STATE["weather"])
    if gps_fresh and now - LAST_NWS > 120:
        try:
            nws = fetch_nws(float(lat), float(lon))
            nws["status"] = "live"
            nws["radarMode"] = "still" if cell_only else "loop"
            weather = nws
            LAST_NWS = now
        except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError):
            if weather.get("forecast"):
                weather["status"] = "offline, last forecast kept but not live"
            else:
                weather = {"status": "no internet", "alerts": [], "forecast": [], "forecastWind": "", "radarMode": "none"}
    elif not gps_fresh:
        weather = {"status": "no GPS", "alerts": [], "forecast": [], "forecastWind": "", "radarMode": "none"}

    alert_ids = {item.get("id") for item in weather.get("alerts") or [] if item.get("id")}
    new_alerts = alert_ids - LAST_ALERT_IDS
    if new_alerts or (falling and not STATE.get("baroFalling")) or (shallow and not STATE.get("shallow")):
        sound_alarm()
    LAST_ALERT_IDS.clear()
    LAST_ALERT_IDS.update(alert_ids)
    save_seen()

    with LOCK:
        STATE.update({
            "sk": sk,
            "fishConnected": fish_connected,
            "windConnected": wind_connected and measured is not None,
            "depthFt": None if surface is None else round(surface * FT, 1),
            "xdcrFt": None if xdcr is None else round(xdcr * FT, 1),
            "tempF": None if temp is None else round((temp - 273.15) * 9 / 5 + 32, 1),
            "depthFresh": depth_fresh,
            "lat": None if lat is None else round(float(lat), 5),
            "lon": None if lon is None else round(float(lon), 5),
            "sogKn": None if sog is None else round(sog * KTS, 1),
            "gpsFresh": gps_fresh,
            "windMeasuredKn": None if measured is None else round(measured * KTS, 0),
            "windLabel": "measured" if wind_connected and measured is not None else "not connected",
            "pressureHpa": None if hpa is None else round(hpa, 1),
            "baroFalling": falling,
            "houseV": None if house_v is None else round(house_v, 1),
            "houseA": None if house_a is None else round(house_a, 1),
            "boatV": None if boat_v is None else round(boat_v, 1),
            "solarW": None if solar is None else round(solar, 0),
            "solarHint": solar_hint,
            "shallow": shallow,
            "weather": weather,
            "network": {
                "modem": net_modem,
                "wifi": wifi.get("name") or "not connected",
                "cellOnly": cell_only,
                "note": "Signal is the USB stick, not a coverage map.",
            },
        })

    station = weather.get("radarStation")
    radar_wait = 300 if cell_only else 90
    if station and weather.get("status") == "live" and now - LAST_RADAR > radar_wait:
        LAST_RADAR = now
        mode = weather.get("radarMode")
        name = f"{station}_0.gif" if mode == "still" else f"{station}_loop.gif"
        url = f"https://radar.weather.gov/ridge/standard/{name}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "bbn-helm"})
            with urllib.request.urlopen(req, timeout=20) as handle:
                raw = handle.read()
            os.makedirs(os.path.dirname(RADAR_PATH), exist_ok=True)
            with open(RADAR_PATH, "wb") as handle:
                handle.write(raw)
        except (OSError, urllib.error.URLError, TimeoutError):
            pass


def load_seen():
    try:
        with open(SEEN_ALERTS, encoding="utf-8") as handle:
            LAST_ALERT_IDS.update(json.load(handle))
    except (OSError, json.JSONDecodeError):
        pass


def save_seen():
    try:
        os.makedirs(os.path.dirname(SEEN_ALERTS), exist_ok=True)
        with open(SEEN_ALERTS, "w", encoding="utf-8") as handle:
            json.dump(sorted(LAST_ALERT_IDS), handle)
    except OSError:
        pass


def collector():
    load_seen()
    while True:
        try:
            collect_once()
        except Exception:
            pass
        time.sleep(5)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _json(self, code, payload):
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _file_abs(self, path, ctype):
        with open(path, "rb") as handle:
            raw = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _file(self, name, ctype):
        path = os.path.join(ROOT, name)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as handle:
            raw = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            self._file("index.html", "text/html; charset=utf-8")
        elif path == "/weather":
            self._file("weather.html", "text/html; charset=utf-8")
        elif path == "/power":
            self._file("power.html", "text/html; charset=utf-8")
        elif path == "/network":
            self._file("network.html", "text/html; charset=utf-8")
        elif path == "/fishing.js":
            self._file("fishing.js", "text/javascript; charset=utf-8")
        elif path == "/fishing.css":
            self._file("fishing.css", "text/css; charset=utf-8")
        elif path == "/api/settings":
            self._json(200, load_settings())
        elif path == "/api/state":
            with LOCK:
                self._json(200, STATE)
        elif path == "/api/radar":
            if os.path.isfile(RADAR_PATH):
                self._file_abs(RADAR_PATH, "image/gif")
            else:
                self.send_error(404)
        else:
            self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._json(400, {"ok": False, "error": "bad json"})
            return
        if path == "/api/settings":
            current = load_settings()
            for key in ("shallowAlarmFt", "shallowAlarmEnabled", "transducerOffsetFt", "draftFt", "openweatherKey", "ina219Enabled"):
                if key in payload:
                    current[key] = payload[key]
            save_settings(current)
            apply_settings(current)
            self._json(200, current)
            return
        if path == "/api/mark":
            try:
                self._json(200, add_mark(payload))
            except (KeyError, TypeError, ValueError, OSError) as err:
                self._json(400, {"ok": False, "error": str(err)})
            return
        self.send_error(404)


def main():
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    if not os.path.exists(SETTINGS):
        packaged = os.path.join(ROOT, "settings.json")
        if os.path.exists(packaged):
            with open(packaged, "r", encoding="utf-8") as handle:
                save_settings(json.load(handle))
        else:
            save_settings(load_settings())
    threading.Thread(target=collector, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()

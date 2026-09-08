#!/usr/bin/env python3
"""Local fishing page and waypoint writer for the cockpit touch screen."""

import json
import os
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
        elif path == "/fishing.js":
            self._file("fishing.js", "text/javascript; charset=utf-8")
        elif path == "/fishing.css":
            self._file("fishing.css", "text/css; charset=utf-8")
        elif path == "/api/settings":
            self._json(200, load_settings())
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
            for key in ("shallowAlarmFt", "shallowAlarmEnabled", "transducerOffsetFt", "draftFt"):
                if key in payload:
                    current[key] = payload[key]
            save_settings(current)
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
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()

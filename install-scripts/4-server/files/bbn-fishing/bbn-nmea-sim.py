#!/usr/bin/env python3
"""Bench NMEA source: changing depth, water temp, and a GPS fix on TCP 10117."""

import math
import socket
import time
from datetime import datetime, timezone


def checksum(sentence):
    value = 0
    for ch in sentence:
        value ^= ord(ch)
    return f"{value:02X}"


def wrap(body):
    return f"${body}*{checksum(body)}\r\n"


def nmea_lat(lat):
    hemi = "N" if lat >= 0 else "S"
    lat = abs(lat)
    deg = int(lat)
    minutes = (lat - deg) * 60
    return f"{deg:02d}{minutes:07.4f}", hemi


def nmea_lon(lon):
    hemi = "E" if lon >= 0 else "W"
    lon = abs(lon)
    deg = int(lon)
    minutes = (lon - deg) * 60
    return f"{deg:03d}{minutes:07.4f}", hemi


def main():
    host = "127.0.0.1"
    port = 10117
    lat = 27.9500
    lon = -82.4500
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    sock.listen(2)
    print(f"NMEA sim listening on {host}:{port}")
    print("Enable the fish_sim Signal K provider, or run bbn-nmea-sim --enable")
    while True:
        conn, _addr = sock.accept()
        t0 = time.time()
        try:
            while True:
                elapsed = time.time() - t0
                depth_m = 3.5 + math.sin(elapsed / 12.0) * 1.8
                if 40 < (elapsed % 90) < 50:
                    depth_m = 0.8
                temp_c = 24.0 + math.sin(elapsed / 40.0) * 0.4
                now = datetime.now(timezone.utc)
                hhmmss = now.strftime("%H%M%S")
                ddmmyy = now.strftime("%d%m%y")
                la, ns = nmea_lat(lat)
                lo, ew = nmea_lon(lon)
                lines = [
                    wrap(f"SDDPT,{depth_m:.1f},0.0,50.0"),
                    wrap(f"YXMTW,{temp_c:.1f},C"),
                    wrap(f"GPRMC,{hhmmss},A,{la},{ns},{lo},{ew},2.4,84.4,{ddmmyy},003.1,W"),
                    wrap(f"GPGGA,{hhmmss},{la},{ns},{lo},{ew},1,08,0.9,1.0,M,0.0,M,,"),
                ]
                conn.sendall("".join(lines).encode("ascii"))
                time.sleep(1)
        except (BrokenPipeError, ConnectionResetError, OSError):
            conn.close()


if __name__ == "__main__":
    main()

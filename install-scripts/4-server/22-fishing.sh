#!/bin/bash -e

# Fishing cockpit: touch page, NMEA bind helpers, chart marks, disabled sensor templates.

install -d -m 0755 /usr/local/share/bbn-fishing
install -m 0644 "$FILE_FOLDER"/bbn-fishing/index.html /usr/local/share/bbn-fishing/
install -m 0644 "$FILE_FOLDER"/bbn-fishing/fishing.js /usr/local/share/bbn-fishing/
install -m 0644 "$FILE_FOLDER"/bbn-fishing/fishing.css /usr/local/share/bbn-fishing/
install -m 0644 "$FILE_FOLDER"/bbn-fishing/settings.json /usr/local/share/bbn-fishing/
install -m 0755 "$FILE_FOLDER"/bbn-fishing/bbn-fishingd.py /usr/local/share/bbn-fishing/bbn-fishingd.py
install -m 0755 "$FILE_FOLDER"/bbn-fishing/bbn-nmea-sim.py /usr/local/share/bbn-fishing/bbn-nmea-sim.py

install -m 0755 "$FILE_FOLDER"/bbn-fishing/bbn-bind-nmea.sh /usr/local/sbin/bbn-bind-nmea
install -m 0755 "$FILE_FOLDER"/bbn-fishing/bbn-chart-kap.sh /usr/local/bin/bbn-chart-kap
install -m 0755 "$FILE_FOLDER"/bbn-fishing/bbn-nmea-sim.sh /usr/local/bin/bbn-nmea-sim

install -d -m 0755 /etc/systemd/system
install -m 0644 "$FILE_FOLDER"/bbn-fishing/bbn-fishing.service /etc/systemd/system/bbn-fishing.service
systemctl enable bbn-fishing.service

install -m 0644 "$FILE_FOLDER"/bbn-fishing/bbn-fishing.desktop /usr/local/share/applications/bbn-fishing.desktop

install -d -o 1000 -g 1000 -m 0755 /home/user/.config/bbn-fishing
if [ ! -f /home/user/.config/bbn-fishing/settings.json ]; then
  install -m 0644 -o 1000 -g 1000 "$FILE_FOLDER"/bbn-fishing/settings.json /home/user/.config/bbn-fishing/settings.json
fi

install -d -o 1000 -g 1000 -m 0755 /home/user/.opencpn/layers
if ! grep -q '^charts:' /etc/group; then
  groupadd charts || true
fi
usermod -a -G charts user || true

# gpsd stays the position source. Fish finder and wind stay off until a cable is bound.
install -d -m 0755 /etc/udev/rules.d

if [ -d /home/signalk/.signalk/plugin-config-data ]; then
  install -m 644 -o signalk -g signalk "$FILE_FOLDER"/signalk-raspberry-pi-ina219.json \
    /home/signalk/.signalk/plugin-config-data/signalk-raspberry-pi-ina219.json
  install -m 644 -o signalk -g signalk "$FILE_FOLDER"/openweather-signalk.json \
    /home/signalk/.signalk/plugin-config-data/openweather-signalk.json
  install -m 644 -o signalk -g signalk "$FILE_FOLDER"/signalk-noaa-weather.json \
    /home/signalk/.signalk/plugin-config-data/signalk-noaa-weather.json
fi

#!/bin/bash -e
# Re-enable the fishing page on a running image. The page is installed with the image.
# Bind a sounder: sudo bbn-bind-nmea fish /dev/ttyUSB0
# Bench without hardware: bbn-nmea-sim
# Custom KAP chart: bbn-chart-kap photo.png north south east west my-spot

if [ ! -x /usr/local/share/bbn-fishing/bbn-fishingd.py ]; then
  echo "Fishing files are not on this card. Build the full image from this repo first." >&2
  exit 1
fi

systemctl enable bbn-fishing.service
systemctl restart bbn-fishing.service
echo "Fishing page: http://127.0.0.1:8765/"
echo "Shallow alarm stays off until you turn it on and confirm transducer offset."
echo "Fish finder NMEA is disabled until: sudo bbn-bind-nmea fish /dev/ttyUSB0"
echo "Wind NMEA is disabled until: sudo bbn-bind-nmea wind /dev/ttyUSB1"
echo "OpenWeather stays off until an API key is set in Signal K."

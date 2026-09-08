#!/bin/bash -e

apt-get install -y zlib1g libqt5sql5 libqt5serialport5 libqt5widgets5 libqt5dbus5 libqt5sql5-sqlite qtchooser

if [ "$LMARCH" == 'arm64' ]; then
  wget https://github.com/bareboat-necessities/lysmarine_gen/releases/download/vTest/pc-navtex_1.0.0.1_arm64.deb -O pc-navtex.deb
fi

apt-get -y -q install ./pc-navtex.deb && rm -f pc-navtex.deb

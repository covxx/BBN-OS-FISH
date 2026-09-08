#!/bin/bash -e

if [ "$BBN_KIND" == "LITE" ] ; then
  exit 0
fi

#apt-get install -y gcc-avr avr-libc arduino-core-avr # avrdude

ARD_URL=https://downloads.arduino.cc
ARD_FILE=arduino-1.8.19-linuxarm.tar.xz
if [ "$LMARCH" == 'arm64' ]; then
  ARD_FILE=arduino-1.8.19-linuxaarch64.tar.xz
fi
# Download and unpack via host /tmp so the archive does not consume image space.
rm -rf /opt/arduino-1.8.19
mkdir -p /tmp/apt-archives
wget -O "/tmp/$ARD_FILE" "$ARD_URL/$ARD_FILE"
xzcat "/tmp/$ARD_FILE" | tar -C /opt -xvf -
rm -f "/tmp/$ARD_FILE"
pushd /opt/arduino-1.8.19
  install -d /root/.config
  ./install.sh
  ./arduino-linux-setup.sh root
popd


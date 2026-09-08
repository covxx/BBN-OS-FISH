#!/bin/bash -e

if [ "$BBN_KIND" == "LITE" ] ; then
  exit 0
fi

apt-get -q -y --no-install-recommends --no-install-suggests install libusb-0.1-4 libusb-1.0-0 \
  avnav mpg123 xvfb wx3.2-i18n python3-psutil

apt-get -q -y install libwxgtk3.2-1=3.2.2+dfsg-2 libglu1-mesa libarchive13 \
  avnav-history-plugin  avnav-more-nmea-plugin avnav-mapproxy-plugin # TODO: ???  avnav-raspi

#apt-get -q -y -o Dpkg::Options::="--force-overwrite" install avnav-oesenc

AGENT="Debian APT-HTTP/1.3 (2.6.1)"
wget --user-agent="$AGENT" -O avnav-ochartsng.deb https://www.wellenvogel.net/software/avnav/downloads/release-ochartsng/20260531/avnav-ochartsng_20260531-raspbian-bookworm_arm64.deb
apt-get -q -y install ./avnav-ochartsng.deb
rm -f avnav-ochartsng.deb

wget --user-agent="$AGENT" -O avnav-sailinstrument-plugin.deb https://www.free-x.de/debian/pool/main/a/avnav-sailinstrument-plugin/avnav-sailinstrument-plugin_20240503_all.deb
apt-get -q -y install ./avnav-sailinstrument-plugin.deb
rm -f avnav-sailinstrument-plugin.deb

install -o 0 -g 0 -d /usr/lib/systemd/system/avnav.service.d
install -o 0 -g 0 -m 0644 "$FILE_FOLDER"/lys-avnav.conf /usr/lib/systemd/system/avnav.service.d/
install -o 0 -g 0 -d /usr/lib/avnav/lysmarine
install -o 0 -g 0 -m 0644 "$FILE_FOLDER"/avnav_server_lysmarine.xml "/usr/lib/avnav/lysmarine/"

install -m 755 "$FILE_FOLDER"/avnav-restart "/usr/local/sbin/avnav-restart"

npm cache clean --force

echo "" >>/etc/sudoers
echo 'user ALL=(ALL) NOPASSWD: /usr/local/sbin/avnav-restart' >>/etc/sudoers

usermod -a -G lirc avnav

systemctl enable avnav

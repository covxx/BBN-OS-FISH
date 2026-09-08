#!/bin/bash -e

apt-get -y -q install can-utils dfu-util

# canboat 8.1's postinst still copies this template, but the package no longer ships it.
mkdir -p /usr/share/canboat/default
if [ ! -e /usr/share/canboat/default/n2kd ]; then
  printf '%s\n' '# placeholder; canboat 8 no longer ships this template' > /usr/share/canboat/default/n2kd
fi
apt-get -y -q install canboat || {
  printf '%s\n' '# placeholder; canboat 8 no longer ships this template' > /usr/share/canboat/default/n2kd
  dpkg --configure canboat
}

yes | cpan install Config::General # for canboat n2kd_monitor

systemctl disable canboat.service || true

install -v -m 0644 "$FILE_FOLDER"/socketcan-interface.service "/etc/systemd/system/socketcan-interface.service"

systemctl disable socketcan-interface.service

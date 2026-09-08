#!/bin/bash -e

if [ "$LMARCH" == 'arm64' ]; then
  wget https://github.com/bareboat-necessities/lysmarine_gen/releases/download/vTest/kplex_1.4.1.3_arm64.deb -O kplex.deb
fi

apt-get -y -q install ./kplex.deb && rm -f kplex.deb

install -v -o 1000 -g 1000 -m 0644 "$FILE_FOLDER"/kplex-lysmarine.conf "/etc/"
install -v -o 1000 -g 1000 -m 0644 "$FILE_FOLDER"/kplex-lysmarine.conf "/etc/kplex.conf"

systemctl disable kplex


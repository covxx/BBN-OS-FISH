#!/bin/bash -e

if [ "$BBN_KIND" == "LITE" ] ; then
  exit 0
fi

apt-get -y -q install  libayatana-appindicator3-1 # TODO: empathy

apt-get clean

# FB messenger
if [ "$LMARCH" == 'armhf' ]; then
  arch=armv7l
elif [ "$LMARCH" == 'arm64' ]; then
  arch=arm64
elif [ "$LMARCH" == 'amd64' ]; then
  arch=x64
else
  arch=$LMARCH
fi

#wget http://ftp.us.debian.org/debian/pool/main/libi/libindicator/libindicator3-7_0.5.0-4_${arch}.deb
#wget http://ftp.us.debian.org/debian/pool/main/liba/libappindicator/libappindicator3-1_0.4.92-7_${arch}.deb
#dpkg -i libindicator3-7_0.5.0-4_${arch}.deb libappindicator3-1_0.4.92-7_${arch}.deb
#rm libindicator3-7_0.5.0-4_${arch}.deb libappindicator3-1_0.4.92-7_${arch}.deb

wget https://github.com/bareboat-necessities/caprine-arm64/releases/download/v2.59.1/caprine_2.59.1_arm64.deb
apt-get -y -q install ./caprine_2.59.1_arm64.deb
chown root:root /
chmod 755 /
rm caprine_2.59.1_arm64.deb

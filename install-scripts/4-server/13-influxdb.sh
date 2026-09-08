#!/bin/bash -e

apt-get clean

if [ "$BBN_KIND" == "LITE" ] ; then
  exit 0
fi

groupadd -g 988 influxdb
useradd -u 982 -g influxdb -r influxdb -d /var/lib/influxdb

apt-get -y -q install telegraf
apt-get -y -q install influxdb || apt-get -y -q install influxdb2 || true
apt-get -y -q install chronograf || true
apt-get -y -q install kapacitor || true

systemctl unmask influxdb || true
systemctl disable influxdb || true
systemctl disable influxdb2 || true
systemctl disable chronograf || true
systemctl disable kapacitor || true
systemctl disable telegraf || true

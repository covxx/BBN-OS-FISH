#!/bin/bash -e

if [ "$BBN_KIND" == "LITE" ] ; then
  exit 0
fi

#apt-get install -y jellyfin

apt-get clean
rm -rf /var/cache/apt/archives/*
rm -rf ~/.cache/pip

# latest-stable moves; the old 10.11.11 filenames 404. Pick the current Bookworm debs.
serverDir="https://repo.jellyfin.org/files/server/debian/latest-stable/arm64"
# Jellyfin 12 depends on jellyfin-ffmpeg8, which conflicts with ffmpeg7.
ffmpegDir="https://repo.jellyfin.org/files/ffmpeg/debian/latest-8.x/arm64"
serverHtml=$(wget -O - "$serverDir/")
ffmpegHtml=$(wget -O - "$ffmpegDir/")

serverDeb=$(echo "$serverHtml" | grep -oE 'jellyfin-server_[^"< ]*deb12_arm64\.deb' | head -n 1)
webDeb=$(echo "$serverHtml" | grep -oE 'jellyfin-web_[^"< ]*deb12_all\.deb' | head -n 1)
metaDeb=$(echo "$serverHtml" | grep -oE 'jellyfin_[^"< ]*deb12_all\.deb' | head -n 1)
ffmpegDeb=$(echo "$ffmpegHtml" | grep -oE 'jellyfin-ffmpeg8_[^"< ]*bookworm_arm64\.deb' | head -n 1)

if [ -z "$serverDeb" ] || [ -z "$webDeb" ] || [ -z "$metaDeb" ] || [ -z "$ffmpegDeb" ]; then
  echo "Could not find Bookworm Jellyfin packages under latest-stable." >&2
  exit 1
fi

echo "Installing $serverDeb $webDeb $metaDeb $ffmpegDeb"
wget -O "$serverDeb" "${serverDir}/${serverDeb//+/%2B}"
wget -O "$webDeb" "${serverDir}/${webDeb//+/%2B}"
wget -O "$metaDeb" "${serverDir}/${metaDeb//+/%2B}"
wget -O "$ffmpegDeb" "${ffmpegDir}/${ffmpegDeb//+/%2B}"

apt-get -y -q install ./"$ffmpegDeb" ./"$serverDeb" ./"$webDeb" ./"$metaDeb"
rm -f ./"$ffmpegDeb" ./"$serverDeb" ./"$webDeb" ./"$metaDeb"

adduser jellyfin audio

systemctl disable jellyfin

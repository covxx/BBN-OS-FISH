#!/bin/bash -xe
cd "$(dirname "$0")"
{
  source ./lib.sh

  MY_CPU_ARCH=$1
  LYSMARINE_VER=$2
  BBN_KIND=$3

  thisArch="raspios"
  cpuArch="arm64"
  # Latest Bookworm (Debian 12) lite, published as oldstable after Trixie took the main folder.
  # Still a two-partition image: p1 FAT boot, p2 ext4 root. 01-boot.sh follows /boot/config.txt.
  imageHost="https://downloads.raspberrypi.com"
  zipName="raspios_oldstable_lite_arm64/images/raspios_oldstable_lite_arm64-2026-06-19/2026-06-18-raspios-bookworm-arm64-lite.img.xz"
  if [ "armhf" == "$MY_CPU_ARCH" ]; then
    cpuArch="armhf"
    imageHost="https://downloads.raspberrypi.org"
    zipName="raspios_lite_armhf/images/raspios_lite_armhf-2025-05-13/2025-05-13-raspios-bookworm-armhf-lite.img.xz"
  fi
  imageSource="${imageHost}/${zipName}"

  checkRoot

  # Create caching folder hierarchy to work with this architecture.
  setupWorkSpace $thisArch

  # Download the official image once. Re-runs reuse cache/$thisArch.
  myCache=./cache/$thisArch
  imageName=$(basename "$zipName" .xz)
  if [ ! -f "$myCache/$imageName" ]; then
    log "Downloading official image from internet."
    wget -c -P "$myCache/" "$imageSource"
    7z e -aoa -o"$myCache/" "$myCache/$(basename "$zipName")"
    rm -f "$myCache/$(basename "$zipName")"
  else
    log "Using cached Raspberry Pi image $imageName"
  fi

  # Copy image file to work folder add temporary space to it.
  inflateImage $thisArch "$myCache/$imageName"

  workImage=./work/$thisArch/"$imageName"
  progress=$myCache/.bbn-progress

  # Do not replace a still-mounted work image. That corrupts the loop file
  # and is what leaves rootfs stuck after a failed unmount.
  if rootfsBusy ./work/$thisArch/rootfs; then
    logErr "Clearing leftover mount before using $workImage"
    umountImageFile $thisArch "$workImage" || exit 1
  fi

  # An incomplete previous build keeps the work image and skips finished stages.
  # BBN_FRESH=1 recopies the inflated image and runs every stage again.
  if [ "${BBN_FRESH:-0}" != "1" ] && [ -f "$progress" ] && [ -f "$workImage" ]; then
    log "Resuming incomplete image (set BBN_FRESH=1 to start over)"
  else
    rm -rf "$myCache/stageCache/.bbn-done"
    rm -f "$progress"
    log "Copying inflated image into the work directory"
    cp -fv "$myCache/$imageName-inflated" "$workImage"
    date -Iseconds > "$progress"
  fi

  # Mount the image and make the binds required to chroot.
  mountImageFile $thisArch "$workImage"

  # Copy the lysmarine and origine OS config files in the mounted rootfs
  addLysmarineScripts $thisArch

  mkRoot=work/${thisArch}/rootfs
  ls -l $mkRoot

  mkdir -p ./cache/${thisArch}/stageCache
  mkdir -p $mkRoot/install-scripts/stageCache
  mkdir -p /run/shm
  mkdir -p $mkRoot/run/shm
  mount -o bind /etc/resolv.conf $mkRoot/etc/resolv.conf
  mount -o bind /dev $mkRoot/dev
  mkdir -p $mkRoot/dev/pts
  mount -t devpts devpts $mkRoot/dev/pts || true
  mount -o bind /sys $mkRoot/sys
  mount -o bind /proc $mkRoot/proc
  mount -o bind /tmp $mkRoot/tmp
  mount --rbind $myCache/stageCache $mkRoot/install-scripts/stageCache
  mount --rbind /run/shm $mkRoot/run/shm

  # The chroot shares this host clock. Step it before apt sees Release files.
  syncHostClock
  mkdir -p "$mkRoot/etc/apt/apt.conf.d" /tmp/apt-archives
  cat > "$mkRoot/etc/apt/apt.conf.d/99bbn-clock-skew" <<'EOF'
Acquire::Max-FutureTime "86400";
Acquire::Check-Valid-Until "false";
Dir::Cache::archives "/tmp/apt-archives/";
APT::Keep-Downloaded-Packages "false";
EOF
  rm -rf "$mkRoot/var/cache/apt/archives/"* || true

  chroot $mkRoot /bin/bash -xe <<EOF
    set -x; set -e; cd /install-scripts; export LMBUILD="raspios"; export BBN_KIND="$BBN_KIND"; ls; chmod +x *.sh; ./install.sh 0 2 4 6 8 a; exit
EOF

  # Unmount. Do not delete stageCache: it is a host bind-mount of git clones.
  pruneImageContents $thisArch
  umountImageFile $thisArch "$workImage"

  ls -l "$workImage"
  if [ ! -x "$myCache/pishrink.sh" ]; then
    wget "https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh" -O "$myCache/pishrink.sh"
    chmod +x "$myCache/pishrink.sh"
  fi
  "$myCache"/pishrink.sh -s "$workImage" || if [ $? == 11 ]; then
    log "Image already shrunk to smallest size"
  fi
  ls -l "$workImage"

  # Renaming the OS and moving it to the release folder.
  if [ "$BBN_KIND" == "LITE" ] ; then
    BBN_IMG=lysmarine-bbn-lite-bookworm_"${LYSMARINE_VER}"-${thisArch}-${cpuArch}.img
  else
    BBN_IMG=lysmarine-bbn-full-bookworm_"${LYSMARINE_VER}"-${thisArch}-${cpuArch}.img
  fi
  cp -v -l "$workImage" ./release/$thisArch/"$BBN_IMG"
  rm -f "$progress"

  exit 0
}

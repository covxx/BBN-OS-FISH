log() {
  echo -e "\e[32m["$(date +'%T')"] \e[1m $1 \e[0m"
}

logErr() {
  echo -e "\e[91m ["$(date +'%T')"] ---> $1 \e[0m"
}

# Create caching folder hierarchy to work with this architecture
setupWorkSpace() {
  thisArch=$1
  mkdir -p ./cache/"$thisArch"/stageCache
  mkdir -p ./work/"$thisArch"/rootfs
  mkdir -p ./work/"$thisArch"/bootfs
  mkdir -p ./release/"$thisArch"
}

# Check if the user run with root privileges
checkRoot() {
  if [ $EUID -ne 0 ]; then
    echo "This tool must be run as root."
    exit 1
  fi
}

# QEMU guests often boot with a slow clock. apt then treats a current
# Release file as "not valid yet" and refuses the update.
syncHostClock() {
  log "Checking build host clock"
  header=""
  if command -v curl >/dev/null 2>&1; then
    header=$(curl -fsI --max-time 20 http://deb.debian.org/debian/ 2>/dev/null | awk -F': ' 'tolower($1)=="date"{print $2}' | tr -d '\r')
  elif command -v wget >/dev/null 2>&1; then
    header=$(wget -qS -O /dev/null --timeout=20 http://deb.debian.org/debian/ 2>&1 | awk -F': ' 'tolower($1) ~ /  *date/{print $2}' | tr -d '\r' | tail -n 1)
  fi

  if [ -n "$header" ]; then
    now=$(date -u +%s)
    remote=$(date -u -d "$header" +%s 2>/dev/null || true)
    if [ -n "$remote" ]; then
      skew=$((remote - now))
      if [ "$skew" -lt 0 ]; then
        abs=$((-skew))
      else
        abs=$skew
      fi
      if [ "$abs" -gt 30 ]; then
        log "Host clock is ${skew}s off Debian. Setting clock from HTTP Date."
        date -u -s "$header" || true
        hwclock --systohc 2>/dev/null || true
      fi
    fi
  fi

  timedatectl set-ntp true >/dev/null 2>&1 || true
}

# True if anything is mounted on rootfs, or the mountpoint directory is not empty.
rootfsBusy() {
  rootfs=$1
  if mountpoint -q "$rootfs" 2>/dev/null; then
    return 0
  fi
  [ -n "$(ls -A "$rootfs" 2>/dev/null)" ]
}

# Drop every mount under rootfs, then detach the image loop devices.
# Never delete files through the mount: a broken ext4 returns "Bad message"
# and, with set -e, that used to abort before umount ran.
umountImageFile() {
  log "un-Mounting"
  thisArch=$1
  imageFile=$2
  rootfs=./work/${thisArch}/rootfs
  absRoot=$(readlink -f "$rootfs")
  absImage=$(readlink -f "$imageFile" 2>/dev/null || echo "$imageFile")

  hadErrexit=0
  case $- in *e*) hadErrexit=1 ;; esac
  set +e

  # Deepest mounts first so bind mounts (dev, proc, stageCache, ...) go away
  # before the partition itself.
  awk -v r="$absRoot" '
    $2 == r || index($2, r "/") == 1 { print length($2), $2 }
  ' /proc/mounts | sort -nr | while read -r _ mp; do
    umount "$mp" || umount -l "$mp" || true
  done

  if mountpoint -q "$absRoot"; then
    umount -R "$absRoot" || umount -Rl "$absRoot" || umount -l "$absRoot" || true
  fi

  kpartx -d "$absImage"
  # Retry detach if the mapper devices were still busy after a lazy unmount.
  for _try in 1 2 3; do
    if ! losetup -j "$absImage" | grep -q .; then
      break
    fi
    sleep 1
    kpartx -d "$absImage"
    losetup -j "$absImage" | while IFS= read -r line; do
      dev=${line%%:*}
      kpartx -d "$dev" || true
      losetup -d "$dev" || true
    done
  done

  # Host-side leftovers only. If this is still a mount, do not rm through it.
  if ! mountpoint -q "$absRoot" && [ -n "$(ls -A "$absRoot" 2>/dev/null)" ]; then
    find "$absRoot" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi

  [ "$hadErrexit" = 1 ] && set -e

  if rootfsBusy "$rootfs"; then
    logErr "$rootfs is still busy. Leftover mounts:"
    awk -v r="$absRoot" '$2 == r || index($2, r "/") == 1 { print }' /proc/mounts
    return 1
  fi
  return 0
}

# Strip build leftovers from a healthy mounted image before packing.
# stageCache is a host bind-mount; unmount it, do not delete it.
pruneImageContents() {
  thisArch=$1
  rootfs=./work/${thisArch}/rootfs
  mountpoint -q "$rootfs" || return 0

  hadErrexit=0
  case $- in *e*) hadErrexit=1 ;; esac
  set +e

  rm -rf "$rootfs/home/border"
  if [ -d "$rootfs/install-scripts/logs" ]; then
    find "$rootfs/install-scripts/logs" -mindepth 1 -delete
  fi
  if [ -d "$rootfs/var/log" ]; then
    find "$rootfs/var/log" -type f -delete
  fi
  if [ -d "$rootfs/tmp" ]; then
    find "$rootfs/tmp" -mindepth 1 -delete
  fi

  [ "$hadErrexit" = 1 ] && set -e
  return 0
}

mountImageFile() {
  thisArch=$1
  imageFile=$2
  mountOpt=$3
  rootfs=./work/${thisArch}/rootfs

  log "Mounting Image File"

  ## A previous run can leave the image mounted. Unmount before attaching it again.
  if rootfsBusy "$rootfs"; then
    logErr "$rootfs is not empty. Previous failure to unmount?"
    if ! umountImageFile "$1" "$2"; then
      exit 1
    fi
  fi

  # Mount the image and make the binds required to chroot.
  losetup -f
  partitions=$(kpartx -sav "$imageFile" | cut -d' ' -f3)
  partQty=$(echo "$partitions" | wc -w)
  echo "$partQty partitions detected."

  # mount partition table in /dev/loop
  loopId=$(echo "$partitions" | grep -oh '[0-9]*' | head -n 1)

  if [ "$partQty" == 2 ]; then
    mount $mountOpt -v /dev/mapper/loop"${loopId}"p2 "$rootfs"/
    if [ ! -d "$rootfs"/boot ]; then mkdir "$rootfs"/boot; fi
    mount $mountOpt -v /dev/mapper/loop"${loopId}"p1 "$rootfs"/boot/
  elif [ "$partQty" == 1 ]; then
    mount $mountOpt -v /dev/mapper/loop"${loopId}"p1 "$rootfs"/
  else
    log "ERROR: unsupported amount of partitions."
    exit 1
  fi
}

inflateImage() {
  thisArch=$1
  imageLocation=$2
  imageLocationInflated=${imageLocation}-inflated

  if [ ! -f "$imageLocationInflated" ]; then
    log "Inflating OS image to have enough space to build BBN OS. "
    cp -fv "${imageLocation}" "$imageLocationInflated"

    if [ "$BBN_KIND" == "LITE" ] ; then
      log "truncate image to 9.2G"
      truncate -s "9216M" "$imageLocationInflated"
    else
      log "truncate image to 16G"
      truncate -s "16G" "$imageLocationInflated"
    fi

    log "resize last partition to 100%"
    partQty=$(fdisk -l "$imageLocationInflated" | grep -o "^$imageLocationInflated" | wc -l)
    parted "$imageLocationInflated" --script "resizepart $partQty 100%"
    fdisk -l "$imageLocationInflated"

    log "Resize the filesystem to fit the partition."
    loopId=$(kpartx -sav "$imageLocationInflated" | cut -d" " -f3 | grep -oh '[0-9]*' | head -n 1)
    sleep 2
    ls -l /dev/mapper/

    e2fsck -y -f /dev/mapper/loop"${loopId}"p"$partQty"
    resize2fs /dev/mapper/loop"${loopId}"p"$partQty"
    sync
    sleep 2
    kpartx -d "$imageLocationInflated" || true
  else
    log "Using Ready to build image from cache"
  fi
}

function addLysmarineScripts() {
  thisArch=$1
  rootfs=./work/${thisArch}/rootfs
  log "copying lysmarine on the image"
  ls "$rootfs"
  if [ -d ./install-scripts ]; then
    scriptSrc=./install-scripts
  else
    scriptSrc=../install-scripts
  fi
  cp -r "$scriptSrc" "${rootfs}"/
  chmod 0775 "${rootfs}"/install-scripts/install.sh
}

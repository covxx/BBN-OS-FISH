#!/bin/bash -xe

echo "Install script for BBN OS :)"

## Check variable declaration
if [[ -z $LMARCH ]]; then
  LMARCH="$(dpkg --print-architecture)"
  export LMARCH
fi
echo "Architecture: $LMARCH"

if [[ -z $LMOS ]]; then
  if [ ! -f /usr/bin/lsb_release ]; then
    apt-get install -y -q lsb-release
  fi
  LMOS="$(lsb_release -id -s | head -1)"
  export LMOS
fi
echo "Base OS: $LMOS"

## This makes less noise in cross-build environment.
export LANG="en_US.UTF-8"
export LANGUAGE=en_US:en
export LC_NUMERIC="C"
export LC_CTYPE="C"
export LC_MESSAGES="C"
export LC_ALL="C"
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a
export MAKEFLAGS="-j$(nproc)"

# A slow QEMU clock makes current Release files look "not valid yet".
# Keep downloaded debs on the host /tmp bind so the image root does not fill up.
mkdir -p /etc/apt/apt.conf.d /tmp/apt-archives
cat > /etc/apt/apt.conf.d/99bbn-clock-skew <<'EOF'
Acquire::Max-FutureTime "86400";
Acquire::Check-Valid-Until "false";
Dir::Cache::archives "/tmp/apt-archives/";
APT::Keep-Downloaded-Packages "false";
EOF
apt-get clean || true
rm -rf /var/cache/apt/archives/* /var/cache/apt/archives/partial || true

# Completed stage scripts are recorded on the host via the stageCache bind-mount
# so a failed build can resume instead of repeating apt/git work.
stampDir=./stageCache/.bbn-done
mkdir -p "$stampDir"

## If no build stage provided, build all stages.
if [ "$#" -gt "0" ]; then
  argumentList="$@"
else
  argumentList="*.*"
fi

set -f
for argument in $argumentList; do # access each element of array
  stage=$(echo "$argument" | cut -d '.' -f 1)
  script=$(echo "$argument" | cut -s -d '.' -f 2)

  if [ ! "$script" ]; then
    script="*"
  fi

  set +f
  for scriptLocation in ./$stage*/$script*.sh; do
    if [ -f "$scriptLocation" ]; then
      stamp="$stampDir/$(echo "$scriptLocation" | tr '/' '_')"
      echo "From request $argument "
      if [ -f "$stamp" ]; then
        echo "Skipping completed $scriptLocation"
        continue
      fi
      echo "Running stage $stage -> $script ( $scriptLocation )"
      export FILE_FOLDER=${scriptLocation%/*}/files/
      chmod +x "$scriptLocation"
      if ! "$scriptLocation"; then
        exit 255
      fi
      touch "$stamp"
    fi
  done
done

echo "Done installing script for BBN OS $ARCH :)"

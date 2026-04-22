#!/bin/bash
set -euo pipefail

# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause

SUITE=resolute
ARCH=arm64
ROOTDIR=${1:-/tmp/rootfs}
KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
MIRRORS=(http://ports.ubuntu.com/ubuntu-ports)

DEFAULT_PACKAGES=(
  init udev sudo vim apt file zstd parted fdisk dosfstools iputils-ping
  wget curl ca-certificates systemd systemd-sysv psmisc ethtool iproute2 openssh-server
  openssh-client patchelf htop util-linux lshw keyutils wpasupplicant strongswan-starter
  tcpdump mtd-utils pciutils hdparm libssl-dev usbutils sysstat lsb-release kexec-tools iptables
  libhugetlbfs0 strongswan-charon dmidecode flex initramfs-tools fbset
  mmc-utils i2c-tools lm-sensors rt-tests linuxptp mosquitto xterm bluez pipewire pipewire-audio
  pipewire-pulse wireplumber locales libspa-0.2-bluetooth net-tools
)

PACKAGES=("${DEFAULT_PACKAGES[@]}")
if [ $# -gt 1 ]; then
  EXTRA_PACKAGES=("${@:2}")
  PACKAGES+=("${EXTRA_PACKAGES[@]}")
fi

echo "sources.list: ${MIRRORS[*]}"

mmdebstrap \
  --arch=$ARCH \
  --aptopt='Acquire::Retries=5' \
  --aptopt='Acquire::http::Timeout=30' \
  --aptopt='Acquire::https::Timeout=30' \
  --aptopt='APT::Get::Assume-Yes=true' \
  --aptopt='DPkg::Options::=--force-confnew' \
  --aptopt='Acquire::Languages="none"' \
  --skip=download/bytecode \
  --variant=standard \
  --components=main,restricted,universe \
  --keyring="$KEYRING" \
  --mode=auto \
  --include="$(IFS=,; echo "${PACKAGES[*]}")" \
  "$SUITE" \
  "$ROOTDIR" \
  "${MIRRORS[@]}"

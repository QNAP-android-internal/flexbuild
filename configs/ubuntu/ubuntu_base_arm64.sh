#!/bin/bash
set -e

# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause

SUITE=resolute
ARCH=arm64
TARGET_DIR=${1:-/tmp/rootfs}
MIRRORS=(http://ports.ubuntu.com/ubuntu-ports)

PACKAGES=(
  init udev sudo vim apt file zstd parted fdisk dosfstools iputils-ping dhcpcd
  wget curl ca-certificates systemd systemd-sysv psmisc ethtool iproute2 openssh-server
  openssh-client patchelf htop util-linux lshw keyutils locales wpasupplicant net-tools
)

mmdebstrap \
  --arch=$ARCH \
  --variant=minbase \
  --components=main,restricted,universe \
  --include="$(IFS=,; echo "${PACKAGES[*]}")" \
  --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --mode=unshare \
  "$SUITE" \
  "$TARGET_DIR" \
  "${MIRRORS[@]}"

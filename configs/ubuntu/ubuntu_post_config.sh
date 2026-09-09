#!/bin/bash
set -euo pipefail

# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause

ROOTDIR=${1:-/tmp/rootfs}

[ -d "$ROOTDIR" ] || { echo "Rootfs directory $ROOTDIR not found"; exit 1; }

echo -e "\n[INFO] setting up Ubuntu rootfs"

mkdir -p "$ROOTDIR"/usr/local/bin \
         "$ROOTDIR"/usr/lib/systemd/system \
         "$ROOTDIR"/etc/udev/rules.d \
         "$ROOTDIR"/etc/modprobe.d \
         "$ROOTDIR"/etc/systemd/system/multi-user.target.wants \
         "$ROOTDIR"/etc/systemd/system/graphical.target.wants \
         "$ROOTDIR"/etc/systemd/system/local-fs.target.wants \
         "$ROOTDIR"/usr/share/wireplumber/wireplumber.conf.d

install -D -m 644 src/system/boot.mount            "$ROOTDIR"/usr/lib/systemd/system/boot.mount
install -D -m 755 tools/flex-installer             "$ROOTDIR"/usr/bin/flex-installer
install -D -m 755 tools/resizerfs                  "$ROOTDIR"/usr/bin/resizerfs
install -D -m 644 src/system/resizerfs.service     "$ROOTDIR"/usr/lib/systemd/system/resizerfs.service
install -D -m 644 src/system/udev/udev-rules-*/*.rules "$ROOTDIR"/etc/udev/rules.d/
install -D -m 755 src/system/distroplatcfg         "$ROOTDIR"/usr/bin/distroplatcfg
install -D -m 644 src/system/platcfg.service       "$ROOTDIR"/usr/lib/systemd/system/platcfg.service
install -D -m 644 src/system/blacklist.conf        "$ROOTDIR"/etc/modprobe.d/blacklist.conf
install -D -m 644 src/system/ts.conf               "$ROOTDIR"/etc/ts.conf.bak
install -D -m 755 src/system/board_id.sh           "$ROOTDIR"/usr/bin/board_id.sh
install -D -m 644 src/system/80-wired.network      "$ROOTDIR"/usr/lib/systemd/network/80-wired.network
install -D -m 755 src/system/debian-post-install-pkg "$ROOTDIR"/usr/bin/
install -D -m 644 src/system/51-bluez-imx.conf       "$ROOTDIR"/usr/share/wireplumber/wireplumber.conf.d/
install -D -m 644 src/system/80-disable-logind.conf  "$ROOTDIR"/usr/share/wireplumber/wireplumber.conf.d/
# Generate GNOME monitors.xml at boot so the GDM login lands on HDMI
# regardless of which HDMI panel is plugged in (reads live EDID).
install -D -m 755 src/system/gnome/gen-monitors.py      "$ROOTDIR"/usr/local/bin/gen-monitors.py
install -D -m 644 src/system/gnome/gen-monitors.service "$ROOTDIR"/usr/lib/systemd/system/gen-monitors.service
install -D -m 755 src/system/edid-fallback/edid-fallback.sh      "$ROOTDIR"/usr/sbin/edid-fallback.sh
install -D -m 644 src/system/edid-fallback/edid-fallback.service "$ROOTDIR"/usr/lib/systemd/system/edid-fallback.service
install -D -m 644 src/system/edid-fallback/rtk-fhd.bin           "$ROOTDIR"/usr/lib/firmware/edid/rtk-fhd.bin
install -D -m 644 src/system/edid-fallback/lg-ultrafine-4k.bin   "$ROOTDIR"/usr/lib/firmware/edid/lg-ultrafine-4k.bin

echo "lontium-lt9611uxd" > "$ROOTDIR"/etc/modules-load.d/lt9611uxd.conf
echo "/dev/mmcblk0 0x700000 0x4000" > "$ROOTDIR"/etc/fw_env.config

install -D -m 644 configs/ubuntu/extra_packages_list "$ROOTDIR"/etc/

chroot "$ROOTDIR" /bin/bash -e <<'EOF'
mkdir -p /usr/local/bin \
         /etc/udev/rules.d \
         /etc/modprobe.d \
         /etc/systemd/system/multi-user.target.wants \
         /etc/systemd/system/graphical.target.wants \
         /etc/systemd/system/local-fs.target.wants

# --- headless remote desktop: seed /etc/skel BEFORE useradd copies it ---
SKEL_GRD=/etc/skel/.local/share/gnome-remote-desktop
SKEL_KR=/etc/skel/.local/share/keyrings
mkdir -p "$SKEL_GRD" "$SKEL_KR"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=imx-remote-desktop \
  -keyout "$SKEL_GRD/tls.key" -out "$SKEL_GRD/tls.crt" >/dev/null 2>&1
chmod 600 "$SKEL_GRD/tls.key"
cat > "$SKEL_KR/login.keyring" <<'KEYRING'
[keyring]
display-name=Login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false

[1]
item-type=0
display-name=GNOME Remote Desktop RDP credentials
secret={'username': <'ubuntu'>, 'password': <'ubuntu'>}
mtime=0
ctime=0

[1:attribute0]
name=xdg:schema
type=string
value=org.gnome.RemoteDesktop.RdpCredentials
KEYRING
chmod 600 "$SKEL_KR/login.keyring"

# User and group setup
id -u ubuntu &>/dev/null || useradd -m -d /home/ubuntu -s /bin/bash ubuntu
getent group wayland &>/dev/null || groupadd wayland
usermod -aG sudo,input,video,wayland,render ubuntu || true
passwd --delete root >/dev/null || true
passwd --delete ubuntu >/dev/null || true

# SSH configuration
grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
grep -q '^PermitEmptyPasswords' /etc/ssh/sshd_config || echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
mkdir -p /etc/dconf/db/local.d /etc/dconf/db/gdm.d /etc/dconf/profile
printf "user-db:user\nsystem-db:local\n" > /etc/dconf/profile/user
cat > /etc/dconf/db/local.d/00-disable-suspend <<'CONF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
CONF
cp /etc/dconf/db/local.d/00-disable-suspend /etc/dconf/db/gdm.d/00-disable-suspend
# The GDM greeter only honours gdm.d if its profile lists system-db:gdm;
# Ubuntu 26.04's stock /usr/share/dconf/profile/gdm omits it.
printf "user-db:user\nsystem-db:gdm\nfile-db:/var/lib/gdm3/greeter-dconf-defaults\n" > /etc/dconf/profile/gdm
# Never blank the screen (idle-delay), and enable the RDP server with the
# skel-seeded TLS pair. view-only defaults to true in g-r-d 50 -> force off
# or clients see the desktop but cannot move the mouse.
cat > /etc/dconf/db/local.d/10-remote-desktop <<'CONF'
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/remote-desktop/rdp]
enable=true
view-only=false
tls-cert='/home/ubuntu/.local/share/gnome-remote-desktop/tls.crt'
tls-key='/home/ubuntu/.local/share/gnome-remote-desktop/tls.key'
CONF
cp /etc/dconf/db/local.d/10-remote-desktop /etc/dconf/db/gdm.d/10-remote-desktop
# dconf-cli is not in the base chroot; the keyfiles get compiled when the
# dconf package lands at first boot (its postinst runs `dconf update`) and
# debian-post-install-pkg runs it again explicitly.
dconf update || true

# systemd 258+ emits OSC 3008 shell-integration issue fix
dpkg-divert --local --rename --add /etc/profile.d/80-systemd-osc-context.sh
dpkg-divert --local --rename --add /usr/lib/tmpfiles.d/20-systemd-osc-context.conf
rm -f /etc/profile.d/80-systemd-osc-context.sh

# systemd service symlinks
mkdir -p /etc/systemd/system/basic.target.wants
ln -sf /lib/systemd/system/resizerfs.service /etc/systemd/system/basic.target.wants/resizerfs.service
ln -sf /lib/systemd/system/gen-monitors.service /etc/systemd/system/graphical.target.wants/gen-monitors.service
ln -sf /lib/systemd/system/edid-fallback.service /etc/systemd/system/multi-user.target.wants/edid-fallback.service

# Symlinks and firmware
ln -sf /boot/tools/perf /usr/local/bin/perf
ln -sf /sbin/init /init
ln -sf /boot/modules /lib/modules

# fix absolute path for libz.so symlink when cross compiling apitrace
ln -sf libz.so.1 /usr/lib/aarch64-linux-gnu/libz.so

# fixup for libtinfo.so needed by tsntool
ln -sf libtinfo.so.6 /usr/lib/aarch64-linux-gnu/libtinfo.so

# fixup for Qt6 app cross-compiling
ln -sf libQt6Quick.so.6 /usr/lib/aarch64-linux-gnu/libQt6Quick.so
ln -sf libQt6OpenGL.so.6 /usr/lib/aarch64-linux-gnu/libQt6OpenGL.so
ln -sf libQt6QmlModels.so.6 /usr/lib/aarch64-linux-gnu/libQt6QmlModels.so
ln -sf libQt6Qml.so.6 /usr/lib/aarch64-linux-gnu/libQt6Qml.so

# fix ping: socket: Operation not permitted
chmod u+s /bin/ping

# Locale setup
sed -i -e "s/.*en_US.UTF-8.*/en_US.UTF-8 UTF-8/" /etc/locale.gen
/usr/sbin/locale-gen >/dev/null 2>&1 || true
echo "localhost" > /etc/hostname
/usr/sbin/update-locale LANG=en_US.UTF-8 || true

# Root user bashrc
cat >> /etc/environment <<'EOT'
COGL_DRIVER=gles2
CLUTTER_DRIVER=gles2
QT_QPA_PLATFORM=wayland
GDK_GL=gles
QT_QUICK_BACKEND=software
EOT

grep -q 'WAYLAND_DISPLAY' /root/.bashrc || \
    printf "\nexport DISPLAY=:0\nexport WAYLAND_DISPLAY=wayland-0\n" >> /root/.bashrc

printf "/usr/lib\n" >> /etc/ld.so.conf.d/01-sdk.conf
{
  echo " * Support:   https://www.nxp.com/support"
  echo " * Licensing: https://lsdk.github.io/eula"
} > /etc/update-motd.d/20-help-text
printf "Build: $(date --rfc-3339 seconds)\n" >> /etc/buildinfo
EOF

printf "%s %s (optimized with NXP-specific hardware acceleration)\n" \
  "${DISTRIB_NAME:-Ubuntu}" "${DISTRIB_VERSION:-lsdk2512}" >> "$ROOTDIR"/etc/issue

mkdir -p "$ROOTDIR"/etc/xdg/weston
cp -f "$FBDIR"/src/system/weston/weston.ini* "$ROOTDIR"/etc/xdg/weston/

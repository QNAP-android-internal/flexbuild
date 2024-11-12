#!/bin/bash
# date:   10/21/2024
# author: Wig Cheng <wigcheng@ieiworld.com>

source setup.env
UBOOT_BRANCH=iei-imx_v2024.04_6.6.23_2.0.0-next
KERNEL_BRANCH=iei-imx-6.6.23-2.0.0-next
CC=aarch64-linux-gnu-
UBOOT_DEFCONFIG=imx8mp_b643_ppc_defconfig
KERNEL_DEFCONFIG=iei_imx8_defconfig
CPU_NUM=16

export CROSS_COMPILE=$CC

bld -m imx8mpevk

# iei added
sudo LANG=C chroot build_lsdk2406/rfs/rootfs_lsdk2406_debian_desktop_arm64  /bin/bash -c " \
    yes "Y" | apt update; \
    yes "Y" | apt install modemmanager gpiod dnsmasq \
"

sudo LANG=C chroot build_lsdk2406/rfs/rootfs_lsdk2406_debian_desktop_arm64  /bin/bash -c " \
    wget https://raw.githubusercontent.com/AsteroidOS/brcm-patchram-plus/refs/heads/master/src/main.c; \
    mv main.c brcm-patchram-plus.c; \
    gcc brcm-patchram-plus.c -o brcm-patchram-plus; \
    mv brcm-patchram-plus /usr/bin/; \
    chmod a+x /usr/bin/brcm-patchram-plus; \
    rm brcm-patchram-plus.c; \
"

sudo LANG=C chroot build_lsdk2406/rfs/rootfs_lsdk2406_debian_desktop_arm64  /bin/bash -c " \
    wget https://raw.githubusercontent.com/QNAP-android-internal/iei-ubuntu-rockchip/bf1bc5443fd7b259e91819a5e632a1d705c61273/overlay/usr/bin/hotspot_script.sh; \
    mv hotspot_script.sh /usr/bin/hotspot_script.sh; \
"

bld packrfs -p IMX

mkdir build_ieibsp
BUILD_PATH=$PWD

cd build_ieibsp

git clone https://github.com/QNAP-android-internal/uboot-imx -b $UBOOT_BRANCH
git clone https://github.com/QNAP-android-internal/kernel_imx.git -b $KERNEL_BRANCH

cd uboot-imx
make ARCH=arm CROSS_COMPILE=$CC "$UBOOT_DEFCONFIG"
make ARCH=arm CROSS_COMPILE=$CC -j"$CPU_NUM"
./install_uboot_imx8.sh -b imx8mp-b643-ppc.dtb
cd -

cd kernel_imx
make ARCH=arm64 CROSS_COMPILE=${CC} "$KERNEL_DEFCONFIG"
make ARCH=arm64 CROSS_COMPILE=${CC} -j"$CPU_NUM"
rm -rf ./modules/
make ARCH=arm64 CROSS_COMPILE=${CC} -j"$CPU_NUM" modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=./modules/
cd -

echo "creating 7.5GiB empty image ..."
rm -rf *.img
dd if=/dev/zero of=test.img bs=1M count=7500
sync

sudo kpartx -av test.img
loop_dev=$(losetup | grep "test.img" | awk  '{print $1}')
(echo "n"; echo "p"; echo; echo "16385"; echo "+64M"; echo "n"; echo "p"; echo; echo "147456"; echo ""; echo "a"; echo "1"; echo "w";) | sudo fdisk "$loop_dev"
sudo kpartx -d "$loop_dev"
sudo losetup -d "$loop_dev"
sync

sudo kpartx -av test.img
loop_dev=$(losetup | grep "test.img" | awk  '{print $1}')
mapper_dev=$(losetup | grep "test.img" | awk  '{print $1}' | awk -F/ '{print $3}')

sudo mkfs.vfat -F 32 /dev/mapper/"$mapper_dev"p1
sudo mkfs.ext4 /dev/mapper/"$mapper_dev"p2

mkdir mnt
sudo mount /dev/mapper/"$mapper_dev"p1 mnt
sudo cp -rv ./kernel_imx/arch/arm64/boot/Image mnt/
sudo cp -rv ./kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-b643-*.dtb mnt/
sudo umount mnt

sudo mount /dev/mapper/"$mapper_dev"p2 mnt
cd mnt
TARGET_ROOTFS=$(ls -al ../../build_lsdk2406/images/rootfs_lsdk2406_debian_desktop_arm64.tar.zst | awk '{print $11}')
sudo tar -I zstd -xvf ../../build_lsdk2406/images/"$TARGET_ROOTFS"
sync
cd lib/
sudo rm -rf modules
sudo rm -rf firmware
cd ..
sudo mkdir -p lib/modules/
sudo mkdir -p lib/firmware/bcmdhd
sudo cp -rv ../kernel_imx/modules/lib/modules/* lib/modules/

# added iei firmware files
sudo cp -rv ../../iei_firmware/imx lib/firmware/

sudo rm -rf opt/imx8-isp/bin/start_isp.sh
sudo touch opt/imx8-isp/bin/start_isp.sh
sudo chmod a+x opt/imx8-isp/bin/start_isp.sh
sudo tee opt/imx8-isp/bin/start_isp.sh << END
#!/bin/sh

AUD_CARD=\`cat /proc/asound/cards |grep 5672 |grep :|awk  '{print \$1}'\`

# alc5672
amixer -c \$AUD_CARD sset 'IN1 Boost' '2'
amixer -c \$AUD_CARD sset 'RECMIXL BST1' 'on'
amixer -c \$AUD_CARD sset 'RECMIXR BST1' 'on'
amixer -c \$AUD_CARD sset 'Sto1 ADC MIXL ADC1' 'on'
amixer -c \$AUD_CARD sset 'Sto1 ADC MIXL ADC2' 'on'
amixer -c \$AUD_CARD sset 'Sto1 ADC MIXR ADC1' 'on'
amixer -c \$AUD_CARD sset 'Sto1 ADC MIXR ADC2' 'on'
amixer -c \$AUD_CARD sset 'Sto2 ADC MIXL ADC1' 'on'
amixer -c \$AUD_CARD sset 'Sto2 ADC MIXL ADC2' 'on'
amixer -c \$AUD_CARD sset 'Sto2 ADC MIXR ADC1' 'on'
amixer -c \$AUD_CARD sset 'Sto2 ADC MIXR ADC2' 'on'
amixer -c \$AUD_CARD sset 'Stereo DAC MIXL DAC L1' 'on'
amixer -c \$AUD_CARD sset 'Stereo DAC MIXR DAC R1' 'on'

amixer -c \$AUD_CARD sset 'HPOVOL MIXL DAC1' 'on'
amixer -c \$AUD_CARD sset 'HPOVOL MIXR DAC1' 'on'
amixer -c \$AUD_CARD sset 'HPO MIX HPVOL' 'on'
amixer -c \$AUD_CARD sset 'PDM1 L Mux' 'Stereo DAC'
amixer -c \$AUD_CARD sset 'PDM1 R Mux' 'Stereo DAC'

#wifi 6 AP6275S detection and initial bluetooth
WIFI_VID=\$(cat /sys/class/mmc_host/mmc0/mmc0\:0001/vendor)
WIFI_PID=\$(cat /sys/class/mmc_host/mmc0/mmc0\:0001/device)

echo 0 > /sys/class/rfkill/rfkill0/state
sleep 1
echo 1 > /sys/class/rfkill/rfkill0/state
sleep 5
if [ "\$WIFI_VID" = "0x02d0" -a "\$WIFI_PID" = "0xaae8" ];then
	bt_firmware_path=/lib/firmware/BCM4362A2_001.003.006.1045.1053.hcd
	baudrate=3000000
	sudo brcm-patchram-plus --enable_hci --no2bytes --use_baudrate_for_download --tosleep 200000 --baudrate "\$baudrate" --patchram "\$bt_firmware_path" /dev/ttymxc0
fi

END

cd ..
sudo umount mnt
rm -rf mnt

sudo dd if=./uboot-imx/imx-mkimage/iMX8M/flash.bin of="$loop_dev" bs=1k seek=32 conv=fsync

sudo kpartx -d "$loop_dev"
sudo losetup -d "$loop_dev"
sync

DATE=$(date +"%Y%m%d")
mv test.img wafer-imx8mp_debian-12-desktop_$DATE.img

cd $BUILD_PATH

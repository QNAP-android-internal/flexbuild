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

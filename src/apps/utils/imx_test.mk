# Copyright 2023-2024 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

# Unit tests for the i.MX BSP


PLATFORM = IMX8

imx_test: libdrm alsa_lib
	@[ $(DESTARCH) != arm64 -o $(SOCFAMILY) != IMX ] && exit || \
	 $(call download_repo,imx_test,apps/utils) && \
	 $(call patch_apply,imx_test,apps/utils) && \
	 if [ ! -d $(DESTDIR)/usr/include/linux ]; then \
	     bld linux-headers -m $(MACHINE); \
	 fi && \
	 sudo cp -rf $(DESTDIR)/usr/include/alsa $(RFSDIR)/usr/include && \
	 $(call fbprint_b,"imx_test") && \
	 cd $(UTILSDIR)/imx_test && \
	 git config --global --add safe.directory $(UTILSDIR)/imx_test && \
	 git config --global --add safe.directory '*' && \
	 find . -name "*.c" -exec sed -i 's/#include <termio.h>/#include <termios.h>/' {} \; && \
	 sed -i 's/#include <termios.h>/#include <termios.h>\n#include <sys\/ioctl.h>/' test/mxc_uart_test/mxc_uart_xmit_test.c && \
	 mkdir -p $(DESTDIR)/opt/unit_tests && \
	 export CC="$(CROSS_COMPILE)gcc --sysroot=$(RFSDIR) -I$(RFSDIR)/usr/include -I$(DESTDIR)/usr/include -O2 -pipe -g -std=gnu11" && \
	 V=0 VERBOSE='' SDKTARGETSYSROOT=$(DESTDIR) PLATFORM=$(PLATFORM) \
	 $(MAKE) -j$(JOBS) $(LOG_MUTE) && \
	 $(MAKE) install DESTDIR=$(DESTDIR)/opt/unit_tests PLATFORM=$(PLATFORM) $(LOG_MUTE) && \
	 $(call fbprint_d,"imx_test")

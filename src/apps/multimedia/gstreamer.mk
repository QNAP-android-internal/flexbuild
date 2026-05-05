# Copyright 2021-2024 NXP
#
# SPDX-License-Identifier: BSD-3-Clause

# https://gstreamer.freedesktop.org

# GStreamer 1.0 framework for streaming media.
# GStreamer is a multimedia framework for encoding and decoding video and sound.
# It supports a wide range of formats including mp3, ogg, avi, mpeg and quicktime.

# introspection=enabled option depends on gobject-introspection for /usr/bin/g-ir-scanner g-ir-compiler on host
# depends on libgirepository1.0-dev for GLib-2.0.gir and GObject-2.0.gir on host
# depends on libgstreamer1.0-dev for /usr/share/gir-1.0/Gst-1.0.gir


gstreamer:
	@[ $(SOCFAMILY) != IMX  ] && exit || \
	 $(call download_repo,gstreamer,apps/multimedia) && \
	 $(call patch_apply,gstreamer,apps/multimedia) && \
	 cd $(MMDIR)/gstreamer && \
	 $(call fbprint_b,"gstreamer") && \
	 export HAVE_PTP_HELPER_CAPABILITIES=0 && \
	 if ! grep -q libexecdir= meson.build; then \
	     sed -i "/pkgconfig_variables =/a\  'libexecdir=\$\{prefix\}/libexec'," meson.build && \
	     sed -i "/pkgconfig_variables =/a\  'datadir=\$\{prefix\}/share'," meson.build; \
	 fi && \
	 sed -e 's%@TARGET_CROSS@%$(CROSS_COMPILE)%g' -e 's%@STAGING_DIR@%$(RFSDIR)%g' \
	     -e 's%@DESTDIR@%$(DESTDIR)%g' $(FBDIR)/src/system/meson.cross > meson.cross && \
	 \
	 rm -rf build_$(DISTROTYPE)_$(ARCH) && \
	 export PKG_CONFIG_LIBDIR=$(RFSDIR)/usr/lib/aarch64-linux-gnu/pkgconfig:$(RFSDIR)/usr/share/pkgconfig && \
	 export PKG_CONFIG_SYSROOT_DIR=$(RFSDIR) && \
	 export PKG_CONFIG_PATH="" && \
	 meson setup build_$(DISTROTYPE)_$(ARCH) \
		--cross-file meson.cross \
		-Dc_args="--sysroot=$(RFSDIR) -I$(DESTDIR)/usr/local/include" \
		-Dc_link_args="-L$(DESTDIR)/usr/lib" \
		--prefix=/usr --buildtype=release --strip \
		-Dintrospection=disabled \
		-Ddoc=disabled \
		-Dexamples=disabled \
		-Ddbghelp=disabled \
		-Dnls=enabled \
		-Dbash-completion=disabled \
		-Dcheck=enabled \
		-Dcoretracers=disabled \
		-Dgst_debug=true \
		-Dlibdw=disabled \
		-Dtests=disabled \
		-Dtools=enabled \
		-Dtracer_hooks=true \
		-Dlibunwind=disabled $(LOG_MUTE) && \
	 ninja -j$(JOBS) -C build_$(DISTROTYPE)_$(ARCH) install $(LOG_MUTE) && \
	 nxp_gst=$$(readlink $(DESTDIR)/usr/lib/libgstreamer-1.0.so.0) && \
	 sudo find $(DESTDIR)/usr/lib/ -maxdepth 1 -name "libgstreamer-1.0.so.0.*" ! -name "$$nxp_gst" -delete && \
	 $(call fbprint_d,"gstreamer")

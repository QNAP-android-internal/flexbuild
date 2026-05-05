# Copyright 2017-2024 NXP
#
# SPDX-License-Identifier: BSD-3-Clause


#gst_python:
gst_python: gstreamer gst_plugins_base
	@[ $(SOCFAMILY) != IMX ] && exit || \
	$(call dl_by_wget,gst_python_tar,gst-python.tar.xz) && \
	if [ ! -d "$(MMDIR)"/gst_python ]; then \
		mkdir -p $(MMDIR)/gst_python; \
		tar xf $(FBDIR)/dl/gst-python.tar.xz --strip-components=1 --wildcards -C $(MMDIR)/gst_python; \
	fi && \
	$(call fbprint_b,"gst_python") && \
	cd $(MMDIR)/gst_python && \
	sed -e 's%@TARGET_CROSS@%$(CROSS_COMPILE)%g' -e 's%@STAGING_DIR@%$(RFSDIR)%g' \
		-e 's%@DESTDIR@%$(DESTDIR)%g' $(FBDIR)/src/system/meson.cross > meson.cross && \
	rm -rf build && \
	PYVER=$$(ls $(RFSDIR)/usr/lib/python3.* -d 2>/dev/null | grep -oP 'python3\.\K[0-9]+' | sort -n | tail -1) && \
	PYVER=$${PYVER:-14} && \
	export PYTHONPATH="$(RFSDIR)/usr/lib/python3.$$PYVER/site-packages:$$PYTHONPATH" && \
	export CC="$(CROSS_COMPILE)gcc --sysroot=$(RFSDIR)" && \
	export CXX="$(CROSS_COMPILE)g++ --sysroot=$(RFSDIR)" && \
	mkdir -p $(RFSDIR)/usr/lib && \
	cp -a $(DESTDIR)/usr/lib/libgstbase-1.0.so* \
		$(DESTDIR)/usr/lib/libgstanalytics-1.0.so* \
		$(RFSDIR)/usr/lib/ && \
	meson setup build \
		-Dtests=disabled \
		-Dplugin=enabled \
		-Dlibpython-dir=$(RFSDIR)/usr/lib \
		--prefix=/usr \
		--buildtype=plain \
		--cross-file meson.cross \
		--libdir=lib \
		--wrap-mode=nodownload $(LOG_MUTE) && \
	ninja -j $(JOBS) -C build install -v $(LOG_MUTE) && \
	CPYVER=$$(ls $(DESTDIR)/usr/lib/python3/dist-packages/gi/overrides/_gi_gst_analytics.cpython-*-x86_64-linux-gnu.so 2>/dev/null | grep -oP 'cpython-\K[0-9]+' | tail -1) && \
	mv $(DESTDIR)/usr/lib/python3/dist-packages/gi/overrides/_gi_gst_analytics.cpython-$${CPYVER}-x86_64-linux-gnu.so \
		$(DESTDIR)/usr/lib/python3/dist-packages/gi/overrides/_gi_gst_analytics.cpython-$${CPYVER}-aarch64-linux-gnu.so && \
	mv $(DESTDIR)/usr/lib/python3/dist-packages/gi/overrides/_gi_gst.cpython-$${CPYVER}-x86_64-linux-gnu.so \
		$(DESTDIR)/usr/lib/python3/dist-packages/gi/overrides/_gi_gst.cpython-$${CPYVER}-aarch64-linux-gnu.so && \
	$(call fbprint_d,"gst_python")

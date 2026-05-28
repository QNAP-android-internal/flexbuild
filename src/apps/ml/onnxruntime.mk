# Copyright 2026 IEI / Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause
#
# NXP-fork onnxruntime with NeutronExecutionProvider for i.MX95.
# Mirrors meta-imx/meta-imx-ml/recipes-libraries/onnxruntime/onnxruntime_1.22.0.bb
# but for the Debian/Ubuntu rootfs path (RFSDIR + DESTDIR convention).
#
# DEPEND: neutron        (provides libNeutronDriver.a + headers via DESTDIR)
# RDEPENDS (in rootfs):  python3.14, python3.14-dev, pybind11-dev,
#                        nlohmann-json3-dev, libprotobuf-dev, libpng-dev, zlib1g-dev
#
# Source is the same git used by the proven-working yocto build:
#   github.com/nxp-imx/onnxruntime-imx.git @ lf-6.12.34_2.1.0
# (override of DEFAULT_REPO_TAG lives in configs/.sdk.cfg)


PYTHON_SITEPACKAGES_DIR = /usr/lib/python3/dist-packages
ORT_BUILD_DIR = $(MLDIR)/onnxruntime/build_$(DISTROTYPE)_$(ARCH)


onnxruntime: neutron
	@[ $${MACHINE:0:5} != imx95 ] && exit || \
	 $(call download_repo,onnxruntime,apps/ml,submod) && \
	 $(call patch_apply,onnxruntime,apps/ml) && \
	 $(call fbprint_b,"onnxruntime") && \
	 export CC="$(CROSS_COMPILE)gcc --sysroot=$(RFSDIR)" && \
	 export CXX="$(CROSS_COMPILE)g++ --sysroot=$(RFSDIR)" && \
	 export CFLAGS="-O2 -pipe -g -fPIC -I$(DESTDIR)/usr/include" && \
	 export CXXFLAGS="-O2 -pipe -g -fPIC -I$(DESTDIR)/usr/include" && \
	 export LDFLAGS="-L$(DESTDIR)/usr/lib" && \
	 export CMAKE_TLS_VERIFY=0 && \
	 ln -sf /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1 /lib/ld-linux-aarch64.so.1 && \
	 mkdir -p $(RFSDIR)/usr/include/neutron && \
	 cp -f $(DESTDIR)/usr/include/neutron/* $(RFSDIR)/usr/include/neutron && \
	 cp -f $(DESTDIR)/usr/lib/libNeutronDriver* $(RFSDIR)/usr/lib/ && \
	 cd $(MLDIR)/onnxruntime && \
	 if [ -d "$(ORT_BUILD_DIR)" ]; then \
		cmake --build $(ORT_BUILD_DIR) --target clean 2>/dev/null || true; \
		rm -rf $(ORT_BUILD_DIR)/CMakeCache.txt $(ORT_BUILD_DIR)/CMakeFiles; \
	 fi && \
	 cmake  -S $(MLDIR)/onnxruntime/cmake \
		-B $(ORT_BUILD_DIR) \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DFETCHCONTENT_FULLY_DISCONNECTED=OFF \
		-Donnxruntime_BUILD_SHARED_LIB=ON \
		-Donnxruntime_ENABLE_PYTHON=ON \
		-Donnxruntime_CROSS_COMPILING=ON \
		-Donnxruntime_BUILD_UNIT_TESTS=OFF \
		-Donnxruntime_USE_NEUTRON=ON \
		-Donnxruntime_USE_KLEIDIAI=ON \
		-DCMAKE_CXX_FLAGS="-I$(DESTDIR)/usr/include -L$(DESTDIR)/usr/lib -Wno-error=maybe-uninitialized -Wno-error=array-bounds -Wno-error=stringop-overflow -Wno-error=uninitialized" \
		-DCMAKE_C_FLAGS="-I$(DESTDIR)/usr/include -L$(DESTDIR)/usr/lib -Wno-error=maybe-uninitialized -Wno-error=array-bounds -Wno-error=stringop-overflow -Wno-error=uninitialized" \
		-DCMAKE_EXE_LINKER_FLAGS="-L$(DESTDIR)/usr/lib" \
		-DPython_EXECUTABLE=/usr/bin/python3.14 \
		-DPython_INCLUDE_DIR=/usr/include/python3.14 \
		-Wno-dev && \
	 cmake --build $(ORT_BUILD_DIR) -j$(JOBS) $(LOG_MUTE) && \
	 rm -f /lib/ld-linux-aarch64.so.1 && \
	 install -d $(DESTDIR)/usr/lib $(DESTDIR)/usr/include/onnxruntime && \
	 install -m 0644 $(ORT_BUILD_DIR)/libonnxruntime.so.1.22.0 $(DESTDIR)/usr/lib/ && \
	 ln -sf libonnxruntime.so.1.22.0 $(DESTDIR)/usr/lib/libonnxruntime.so.1 && \
	 ln -sf libonnxruntime.so.1 $(DESTDIR)/usr/lib/libonnxruntime.so && \
	 install -m 0644 $(ORT_BUILD_DIR)/libonnxruntime_providers_shared.so $(DESTDIR)/usr/lib/ 2>/dev/null || true && \
	 cp -rf $(MLDIR)/onnxruntime/include/onnxruntime/core/session/*.h $(DESTDIR)/usr/include/onnxruntime/ && \
	 cp -f $(MLDIR)/onnxruntime/include/onnxruntime/core/providers/neutron/neutron_provider_factory.h $(DESTDIR)/usr/include/onnxruntime/ 2>/dev/null || true && \
	 install -d $(DESTDIR)/$(PYTHON_SITEPACKAGES_DIR) && \
	 cp -rf $(ORT_BUILD_DIR)/onnxruntime $(DESTDIR)/$(PYTHON_SITEPACKAGES_DIR)/ && \
	 rm -f $(DESTDIR)/$(PYTHON_SITEPACKAGES_DIR)/onnxruntime/capi/libonnxruntime.so* && \
	 find $(DESTDIR)/$(PYTHON_SITEPACKAGES_DIR) -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
	 $(call fbprint_d,"onnxruntime")

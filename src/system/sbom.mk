# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause
#
# SBOM generation for a flexbuild-produced rootfs.
#
# Invoke via:
#     bld sbom -r ubuntu -m imx95evk
#
# or directly:
#     make -f src/system/sbom.mk sbom \
#         RFSDIR=build_lsdk2512/rfs/rootfs_lsdk2512_ubuntu_imx95evk \
#         SBOMDIR=build_lsdk2512/sbom/ubuntu_imx95evk
#
# Tools used:
#   syft         - Anchore SBOM generator (scans rootfs dir -> CycloneDX/SPDX)
#   grype        - Anchore vulnerability scanner (SBOM -> CVE + CycloneDX VEX)
#                  (only needed for `make vex`)
#
# Output files in $(SBOMDIR):
#   syft-scan.cdx.json     - CycloneDX format (apt + auto-detected packages)
#   syft-scan.spdx.json    - SPDX format
#   sbom-complete.cdx.json - merged with proprietary-components.cdx.json
#   cve-vex.cdx.json       - CycloneDX VEX (grype's CDX output IS a VEX doc)
#   cve-report.txt         - human-readable CVE table
#
# `make sbom` produces the SBOM only. `make vex` runs a CVE scan on top and
# emits a CycloneDX VEX document (per CDX 1.4+ spec: VEX is CDX with
# `vulnerabilities`). It does not gate the build on CVE severity.

FBDIR     ?= $(CURDIR)
SBOMSRC   := $(FBDIR)/src/system

RFSDIR    ?= $(error RFSDIR is not set. Build the rootfs first or pass RFSDIR=<path>.)
SBOMDIR   ?= $(FBDIR)/build_lsdk2512/sbom

PROPRIETARY_CDX := $(SBOMSRC)/proprietary-components.cdx.json
MERGE_SCRIPT    := $(SBOMSRC)/merge_sbom.py
GEN_FLEXBUILD   := $(SBOMSRC)/gen_flexbuild_components.py
SDK_CFG         := $(FBDIR)/configs/.sdk.cfg
SDK_YML         := $(FBDIR)/configs/sdk.yml

SYFT_CDX        := $(SBOMDIR)/syft-scan.cdx.json
SYFT_SPDX       := $(SBOMDIR)/syft-scan.spdx.json
FLEXBUILD_CDX   := $(SBOMDIR)/flexbuild-components.cdx.json

# Branded output filenames per IEI convention:
#   IEI_UBUNTU_V<distro>-<rev>_<board>-SBOM_CYCLONEDX-{1.6,VEX}_<yyyymmdd>.json
#
#   PRODUCT_LINE   product-line prefix, override for non-IEI builds
#   DISTRO_VERSION V<Ubuntu VERSION_ID>, read from the rootfs's os-release
#   REV_TAG        latest `R*`-prefixed git tag (product release marker);
#                  DEV when none exists
#   BOARD_TAG      board short-name, override for boards other than SMARC-IMX95
#   DATE           yyyymmdd at generation time
PRODUCT_LINE   ?= IEI_UBUNTU
BOARD_TAG      ?= SMARC-IMX95
# Prefer PRETTY_NAME so the point release (e.g. 26.04.1) shows up once
# Canonical ships it; on pre-releases the field has no minor and we get
# just "26.04". VERSION_ID never carries the point release on Ubuntu.
DISTRO_VERSION ?= V$(shell grep '^PRETTY_NAME=' $(RFSDIR)/etc/os-release 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo ?.??)
REV_TAG        ?= $(shell cd $(FBDIR) && git describe --tags --abbrev=0 --match 'R*' 2>/dev/null || echo DEV)
DATE           ?= $(shell date +%Y%m%d)
BRAND          := $(PRODUCT_LINE)_$(DISTRO_VERSION)-$(REV_TAG)_$(BOARD_TAG)-SBOM

MERGED          := $(SBOMDIR)/$(BRAND)_CYCLONEDX-1.6_$(DATE).json
VEX_CDX         := $(SBOMDIR)/$(BRAND)_CYCLONEDX-VEX_$(DATE).json
CVE_REPORT_TXT  := $(SBOMDIR)/$(BRAND)_CVE-REPORT_$(DATE).txt

.PHONY: sbom vex check-tools check-grype install-tools scan flexbuild-components merge quick-scan clean

sbom: merge
	@echo
	@echo "=== SBOM generation complete ==="
	@echo "  $(MERGED)"
	@if [ -f $(MERGED) ]; then \
	    total=$$(python3 -c "import json; print(len(json.load(open('$(MERGED)')).get('components', [])))" 2>/dev/null || echo "?"); \
	    echo "  total components: $$total"; \
	fi

check-tools:
	@command -v syft >/dev/null 2>&1 || { \
	    echo "ERROR: syft not found on PATH."; \
	    echo "       Run 'bld sbom install-tools' or install manually:"; \
	    echo "         curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"; \
	    exit 1; \
	}

check-grype:
	@command -v grype >/dev/null 2>&1 || { \
	    echo "ERROR: grype not found on PATH. Run 'bld sbom install-tools'."; exit 1; \
	}

install-tools:
	@echo "Installing syft (Anchore SBOM generator)..."
	curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin
	@echo "Installing grype (Anchore vulnerability scanner)..."
	curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin
	@echo "Done. Versions: $$(syft --version) / $$(grype --version)"

scan: check-tools
	@[ -d "$(RFSDIR)" ] || { echo "ERROR: RFSDIR=$(RFSDIR) does not exist."; exit 1; }
	@mkdir -p $(SBOMDIR)
	@echo "=== Scanning $(RFSDIR) with syft ==="
	syft dir:$(RFSDIR) \
	    -o cyclonedx-json@1.6=$(SYFT_CDX) \
	    -o spdx-json=$(SYFT_SPDX)
	@echo
	@echo "Syft scan complete:"
	@echo "  CycloneDX: $(SYFT_CDX)"
	@echo "  SPDX:      $(SYFT_SPDX)"

flexbuild-components: scan
	@echo "=== Generating flexbuild source-built components manifest from .sdk.cfg ==="
	@python3 $(GEN_FLEXBUILD) \
	    --sdk-cfg $(SDK_CFG) \
	    --sdk-yml $(SDK_YML) \
	    -o $(FLEXBUILD_CDX)

merge: flexbuild-components
	@echo "=== Merging supplemental CycloneDX manifests ==="
	@EXTRAS=""; \
	[ -f "$(PROPRIETARY_CDX)" ] && EXTRAS="$$EXTRAS $(PROPRIETARY_CDX)"; \
	[ -f "$(FLEXBUILD_CDX)" ]   && EXTRAS="$$EXTRAS $(FLEXBUILD_CDX)"; \
	if [ -n "$$EXTRAS" ]; then \
	    python3 $(MERGE_SCRIPT) $(SYFT_CDX) $$EXTRAS -o $(MERGED); \
	else \
	    echo "(no supplemental manifests found, using syft scan as-is)"; \
	    cp $(SYFT_CDX) $(MERGED); \
	fi

# CycloneDX VEX = grype's cyclonedx output on the merged SBOM. Grype emits
# a CDX doc with a `vulnerabilities` array, which is exactly what CDX 1.4+
# calls a VEX document (see cyclonedx.org/capabilities/vex).
vex: merge check-grype
	@echo "=== Running grype on $(notdir $(MERGED)) ==="
	@grype sbom:$(MERGED) -o cyclonedx-json=$(VEX_CDX) -o table=$(CVE_REPORT_TXT) || true
	@# grype has no `@1.6` version pin like syft; it emits CDX 1.7 which
	@# Dependency-Track's current parser rejects. Rewrite the field in place.
	@sed -i 's/"specVersion": *"1\.[0-9]*"/"specVersion": "1.6"/' $(VEX_CDX)
	@echo
	@echo "VEX (CycloneDX): $(VEX_CDX)"
	@echo "CVE table:       $(CVE_REPORT_TXT)"
	@if [ -f $(VEX_CDX) ]; then \
	    n=$$(python3 -c "import json; print(len(json.load(open('$(VEX_CDX)')).get('vulnerabilities', [])))" 2>/dev/null || echo "?"); \
	    echo "vulnerabilities found: $$n"; \
	fi

# Quick stdout-only scan, no files written. Handy for `bld sbom quick-scan`.
quick-scan: check-tools
	@[ -d "$(RFSDIR)" ] || { echo "ERROR: RFSDIR=$(RFSDIR) does not exist."; exit 1; }
	syft dir:$(RFSDIR) -o table

clean:
	rm -rf $(SBOMDIR)

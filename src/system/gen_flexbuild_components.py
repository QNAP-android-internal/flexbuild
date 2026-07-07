#!/usr/bin/env python3
# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause
"""
Generate a CycloneDX manifest of flexbuild source-built components by
parsing configs/.sdk.cfg (and falling back to configs/sdk.yml for
upstream URLs). Each `repo_<name>_ver="..."` line in .sdk.cfg becomes
one component in the output JSON, with version and (when discoverable)
the upstream repository URL.

These components are typically .so/.a files placed under
build_lsdk2512/apps/apps_<distro>_<machine>/ by `bld apps` and merged
into the rootfs by `bld merge-apps`. They are not detected by syft
because they are not registered in dpkg's package database.

Usage:
    python3 gen_flexbuild_components.py \
        --sdk-cfg configs/.sdk.cfg \
        --sdk-yml configs/sdk.yml \
        -o flexbuild-components.cdx.json
"""

import argparse
import json
import re
import sys
from pathlib import Path


def parse_sdk_cfg(path):
    """Yield (name, version) tuples for every `repo_NAME_ver="VER"` entry."""
    pattern = re.compile(r'^\s*repo_([a-zA-Z0-9_]+)_ver\s*=\s*"([^"]+)"\s*$')
    if not Path(path).is_file():
        return
    with open(path) as f:
        for line in f:
            m = pattern.match(line)
            if m:
                yield m.group(1), m.group(2)


def parse_sdk_yml(path):
    """Return {repo_name: {'url': '...', 'ver': '...'}} from sdk.yml.

    Uses a small line-based parser to avoid pulling pyyaml as a dep.
    """
    out = {}
    if not Path(path).is_file():
        return out
    current = None
    with open(path) as f:
        for line in f:
            # Top-level `repo:` block delimiter, treat as just context.
            m_name = re.match(r"^  ([a-zA-Z0-9_]+):\s*$", line)
            if m_name:
                current = m_name.group(1)
                out.setdefault(current, {})
                continue
            if current is None:
                continue
            m_kv = re.match(r"^\s{4,}(url|ver|md5):\s*(\S+.*?)\s*$", line)
            if m_kv:
                out[current][m_kv.group(1)] = m_kv.group(2)
                continue
            # Blank line or new top-level entry resets context.
            if line.strip() == "":
                current = None
    return out


def build_component(name, version, url=None):
    """Build one CycloneDX component dict."""
    comp = {
        "type": "library",
        "name": name,
        "version": version,
        "supplier": {"name": "flexbuild (source-built)"},
        "scope": "optional",
        "properties": [
            {"name": "flexbuild:source", "value": "configs/.sdk.cfg"},
        ],
    }
    if url:
        comp["properties"].append({"name": "flexbuild:upstream", "value": url})
        if url.endswith(".git"):
            # Best-effort PURL for github/gitlab refs.
            m = re.match(r"https?://(?:www\.)?(github|gitlab)\.com/([^/]+)/([^/.]+)", url)
            if m:
                host, owner, repo = m.groups()
                comp["purl"] = f"pkg:{host}/{owner}/{repo}@{version}"
    return comp


def main():
    parser = argparse.ArgumentParser(
        description="Generate CycloneDX manifest of flexbuild source-built components"
    )
    parser.add_argument("--sdk-cfg", default="configs/.sdk.cfg",
                        help="Path to .sdk.cfg (default: configs/.sdk.cfg)")
    parser.add_argument("--sdk-yml", default="configs/sdk.yml",
                        help="Path to sdk.yml for URL lookup (default: configs/sdk.yml)")
    parser.add_argument("-o", "--output", required=True, help="Output CycloneDX JSON")
    args = parser.parse_args()

    yml = parse_sdk_yml(args.sdk_yml)
    components = []
    for name, version in parse_sdk_cfg(args.sdk_cfg):
        url = yml.get(name, {}).get("url")
        components.append(build_component(name, version, url=url))

    if not components:
        print(f"WARNING: no `repo_*_ver` entries found in {args.sdk_cfg}",
              file=sys.stderr)

    cdx = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "metadata": {
            "component": {
                "type": "firmware",
                "name": "flexbuild-source-built",
                "description": (
                    "Components built from source by flexbuild recipes; "
                    "versions are taken from configs/.sdk.cfg at SBOM generation time."
                ),
            }
        },
        "components": components,
    }

    with open(args.output, "w") as f:
        json.dump(cdx, f, indent=2)

    print(f"Wrote {len(components)} components to {args.output}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Copyright 2026 IEI Integration Corp.
# Author: Wig Cheng
#
# SPDX-License-Identifier: BSD-3-Clause
"""
Merge a Syft-generated CycloneDX SBOM with one or more supplemental
CycloneDX manifests (proprietary blobs, flexbuild source-built
components, ...). Produces a single CycloneDX JSON containing every
component reachable by automated scanning + every entry from each
supplemental manifest.

Usage:
    python3 merge_sbom.py <base.cdx.json> <extra1.cdx.json> [<extraN.cdx.json>...] -o <merged.cdx.json>
"""

import argparse
import json
import uuid
from datetime import datetime, timezone


def load_json(path):
    with open(path, "r") as f:
        return json.load(f)


def merge_one(merged, extra):
    """Merge `extra` components into `merged` in place. Dedup by (name, version).
    Returns the number of components added."""
    merged.setdefault("components", [])
    existing = {
        (c.get("name", ""), c.get("version", ""))
        for c in merged["components"]
    }
    added = 0
    for comp in extra.get("components", []):
        key = (comp.get("name", ""), comp.get("version", ""))
        if key in existing:
            continue
        merged["components"].append(comp)
        existing.add(key)
        added += 1
    return added


def merge_all(base_sbom, extras):
    """Merge every extra into base_sbom (shallow-copied)."""
    merged = dict(base_sbom)
    merged.setdefault("metadata", {}).setdefault("properties", [])

    for extra_path, extra in extras:
        added = merge_one(merged, extra)
        merged["metadata"]["properties"].append({
            "name": "sbom:merge-info",
            "value": (f"Merged {added} components from "
                      f"{extra.get('metadata', {}).get('component', {}).get('name', extra_path)}"),
        })

    merged["metadata"]["timestamp"] = datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    merged["serialNumber"] = f"urn:uuid:{uuid.uuid4()}"
    return merged


def main():
    parser = argparse.ArgumentParser(
        description="Merge a Syft SBOM with one or more supplemental CycloneDX manifests"
    )
    parser.add_argument("base_sbom", help="Base CycloneDX JSON (typically syft output)")
    parser.add_argument("extra_sboms", nargs="+",
                        help="Supplemental CycloneDX JSONs to merge in")
    parser.add_argument("-o", "--output", required=True, help="Output merged CycloneDX JSON")
    args = parser.parse_args()

    base = load_json(args.base_sbom)
    extras = [(p, load_json(p)) for p in args.extra_sboms]
    merged = merge_all(base, extras)

    with open(args.output, "w") as f:
        json.dump(merged, f, indent=2)

    total = len(merged.get("components", []))
    print(f"Merged SBOM written to {args.output} ({total} total components)")


if __name__ == "__main__":
    main()

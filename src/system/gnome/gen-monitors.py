#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
#
# Generate GNOME mutter monitors.xml at boot from the currently-attached
# displays' EDIDs. Picks the highest-priority connector type (HDMI before
# LVDS) as the primary logical monitor and disables the rest. Hardware-
# agnostic: replacing the HDMI panel with a different model still results
# in HDMI as the primary, because we read each EDID live at boot.
#
# Designed to run before gdm.service so the login greeter lands on the
# right output. Each connector's monitorspec (vendor/product/serial) is
# extracted from the EDID descriptor blocks the way mutter normalizes
# them -- not the base-block numeric product/serial codes.

import os
import re
import struct
import sys
from pathlib import Path

DRM_DIR = Path("/sys/class/drm")
GREETER_PATH = Path("/var/lib/gdm3/seat0/config/monitors.xml")
SKEL_PATH = Path("/etc/skel/.config/monitors.xml")
HOMES_DIR = Path("/home")

CONNECTOR_PRIORITY = ["HDMI", "DP", "eDP", "LVDS", "DSI", "VGA"]

# Mutter renames kernel DRM connector type names (the prefix before the
# numeric id) for its monitorspec.connector value. The kernel exposes
# e.g. "HDMI-A-1"; mutter shortens this to "HDMI-1".
_CONNECTOR_RENAME = [
    (re.compile(r"^HDMI-A-"), "HDMI-"),
    (re.compile(r"^HDMI-B-"), "HDMI-"),
    (re.compile(r"^DP-"), "DP-"),
]


def normalize_connector(sysfs_name):
    """Convert kernel DRM connector name (HDMI-A-1) to mutter's name (HDMI-1)."""
    for pat, repl in _CONNECTOR_RENAME:
        if pat.match(sysfs_name):
            return pat.sub(repl, sysfs_name)
    return sysfs_name


def parse_edid_vendor(edid):
    """3-char manufacturer ID from EDID bytes 8-9."""
    mid = struct.unpack(">H", edid[8:10])[0]
    return "".join(chr(((mid >> s) & 0x1F) + ord("A") - 1) for s in (10, 5, 0))


def parse_edid_descriptors(edid):
    """
    Walk the four 18-byte descriptor blocks at offsets 54/72/90/108 and
    return (monitor_name, serial_string). Either may be None if not
    present. Mutter prefers these strings over the base-block numeric
    product code and serial number when present.
    """
    name = None
    serial = None
    for offset in (54, 72, 90, 108):
        block = edid[offset : offset + 18]
        if len(block) < 18:
            break
        # Bytes 0-1 == 0 marks a non-timing descriptor; byte 3 is the tag.
        if block[0] != 0 or block[1] != 0:
            continue
        tag = block[3]
        text = block[5:18].split(b"\n", 1)[0].decode("ascii", errors="replace").rstrip()
        if tag == 0xFC:  # Display Product Name
            name = text or name
        elif tag == 0xFF:  # Display Product Serial Number
            serial = text or serial
    return name, serial


# Connector types that MUST have real EDID -- if empty at boot, the
# LT9611UXD (or equivalent HDMI bridge) hasn't finished its I2C read yet.
# We refuse to write an "unknown" spec for these and abort instead, so we
# don't clobber a previously-good monitors.xml. Panels wired without EDID
# (LVDS on this board, some DSI) legitimately have no descriptor and pass
# through as vendor/product/serial=unknown.
_EDID_REQUIRED_PREFIXES = ("HDMI", "DP")


def list_connected():
    for d in sorted(DRM_DIR.glob("card*-*")):
        try:
            if (d / "status").read_text().strip() != "connected":
                continue
            edid = (d / "edid").read_bytes()
        except OSError:
            continue
        # /sys/class/drm/cardN-CONNECTOR -> CONNECTOR
        connector_sysfs = d.name.split("-", 1)[1]
        connector = normalize_connector(connector_sysfs)

        if len(edid) >= 128:
            vendor = parse_edid_vendor(edid)
            name, serial = parse_edid_descriptors(edid)
            # Fallback to numeric fields when descriptor strings are absent
            # (mutter does the same and stores the numeric value as a string).
            if not name:
                product_code = struct.unpack("<H", edid[10:12])[0]
                name = f"0x{product_code:04x}" if product_code else "unknown"
            if not serial:
                numeric_serial = struct.unpack("<I", edid[12:16])[0]
                serial = str(numeric_serial) if numeric_serial else "unknown"
        elif connector.startswith(_EDID_REQUIRED_PREFIXES):
            # HDMI/DP with empty EDID = bridge hasn't finished reading.
            # Signal caller to bail out; mustn't emit a bogus spec.
            raise RuntimeError(
                f"EDID for {connector} is empty (bridge not ready?); "
                "refusing to write bogus monitorspec"
            )
        else:
            # No EDID (typical for the LVDS panel on the i.MX95 EVK).
            vendor = "unknown"
            name = "unknown"
            serial = "unknown"

        try:
            mode = next(
                m for m in (d / "modes").read_text().splitlines() if m
            )
        except (OSError, StopIteration):
            mode = "1024x768"

        yield connector, vendor, name, serial, mode


def priority(connector):
    for i, prefix in enumerate(CONNECTOR_PRIORITY):
        if connector.startswith(prefix):
            return i
    return len(CONNECTOR_PRIORITY)


def parse_mode(mode_str):
    try:
        wh = mode_str.split("@")[0].rstrip("ip")
        w, h = wh.split("x")
        return int(w), int(h)
    except (ValueError, IndexError):
        return 1024, 768


def build_xml(displays):
    """displays already sorted; first entry is primary, rest are disabled."""
    primary = displays[0]
    others = displays[1:]
    conn, vendor, product, serial, mode = primary
    w, h = parse_mode(mode)

    lines = [
        '<monitors version="2">',
        "  <configuration>",
        "    <layoutmode>logical</layoutmode>",
        "    <logicalmonitor>",
        "      <x>0</x>",
        "      <y>0</y>",
        "      <scale>1</scale>",
        "      <primary>yes</primary>",
        "      <monitor>",
        "        <monitorspec>",
        f"          <connector>{conn}</connector>",
        f"          <vendor>{vendor}</vendor>",
        f"          <product>{product}</product>",
        f"          <serial>{serial}</serial>",
        "        </monitorspec>",
        "        <mode>",
        f"          <width>{w}</width>",
        f"          <height>{h}</height>",
        "          <rate>60.000</rate>",
        "        </mode>",
        "      </monitor>",
        "    </logicalmonitor>",
    ]
    if others:
        lines.append("    <disabled>")
        for conn, vendor, product, serial, _ in others:
            lines.extend(
                [
                    "      <monitorspec>",
                    f"        <connector>{conn}</connector>",
                    f"        <vendor>{vendor}</vendor>",
                    f"        <product>{product}</product>",
                    f"        <serial>{serial}</serial>",
                    "      </monitorspec>",
                ]
            )
        lines.append("    </disabled>")
    lines += ["  </configuration>", "</monitors>", ""]
    return "\n".join(lines)


def write_atomic(path, content, mode=0o644, uid_gid=None):
    """Write file then set perms/owner. Skips owner change if uid_gid is None."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content)
    os.chmod(tmp, mode)
    if uid_gid is not None:
        try:
            os.chown(tmp, *uid_gid)
        except (OSError, KeyError):
            pass
    tmp.replace(path)


def lookup_uid_gid(name):
    """Best-effort uid/gid lookup; returns None on failure."""
    try:
        import pwd
        e = pwd.getpwnam(name)
        return (e.pw_uid, e.pw_gid)
    except (KeyError, ImportError):
        return None


def main():
    try:
        displays = list(list_connected())
    except RuntimeError as e:
        # HDMI/DP EDID not ready. Keep the existing monitors.xml (if any)
        # so the previous boot's good config survives this boot.
        print(f"gen-monitors: {e}", file=sys.stderr)
        print("gen-monitors: leaving existing monitors.xml untouched", file=sys.stderr)
        return 0
    if not displays:
        print("gen-monitors: no connected displays, nothing to write", file=sys.stderr)
        return 0

    displays.sort(key=lambda d: priority(d[0]))
    xml = build_xml(displays)
    primary_name = displays[0][0]
    print(
        f"gen-monitors: primary={primary_name}, "
        f"disabled={[d[0] for d in displays[1:]] or 'none'}",
        file=sys.stderr,
    )

    # 1) GDM greeter login screen. Mutter reads this via $XDG_CONFIG_HOME.
    #    Only rewrite (and signal a gdm restart) if the content actually
    #    changed -- restarting gdm while the greeter is mid-init races and
    #    leaves persistent breakage on subsequent boots. ponytail: idempotent.
    gdm_owner = lookup_uid_gid("gdm") or lookup_uid_gid("Debian-gdm")
    try:
        greeter_changed = GREETER_PATH.read_text() != xml
    except (FileNotFoundError, OSError):
        greeter_changed = True
    if greeter_changed:
        write_atomic(GREETER_PATH, xml, mode=0o644, uid_gid=gdm_owner)
        Path("/run/gen-monitors.need-restart").touch()

    # 2) /etc/skel for any future useradd. Don't write if a real user has
    #    already customized something there.
    if not SKEL_PATH.exists():
        write_atomic(SKEL_PATH, xml, mode=0o644)

    # 3) Existing user homes: seed monitors.xml only if user hasn't
    #    configured displays themselves (file absent).
    if HOMES_DIR.is_dir():
        for home in sorted(HOMES_DIR.iterdir()):
            if not home.is_dir():
                continue
            user_xml = home / ".config" / "monitors.xml"
            if user_xml.exists():
                continue
            try:
                st = home.stat()
                write_atomic(user_xml, xml, mode=0o644, uid_gid=(st.st_uid, st.st_gid))
            except OSError as e:
                print(f"gen-monitors: skipping {user_xml}: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())

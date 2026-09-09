#!/bin/sh

find_hdmi() {
    for c in /sys/class/drm/card*-HDMI-A-1; do
        [ -e "$c/status" ] || continue
        CONN=$c
        CARD=${c#/sys/class/drm/card}; CARD=${CARD%%-*}
        OVERRIDE=/sys/kernel/debug/dri/$CARD/HDMI-A-1/edid_override
        return 0
    done
    return 1
}
CONN=; OVERRIDE=

i=0
while ! find_hdmi && [ $i -lt 150 ]; do
    sleep 0.1
    i=$((i + 1))
done
[ -n "$CONN" ] || exit 0

i=0
while [ $i -lt 10 ]; do
    EDID_SIZE=$(wc -c < "$CONN/edid" 2>/dev/null || echo 0)
    [ "$EDID_SIZE" -gt 0 ] && exit 0
    [ $i -eq 5 ] && echo detect > "$CONN/status" 2>/dev/null
    sleep 1
    i=$((i + 1))
done

STATUS=$(cat "$CONN/status" 2>/dev/null)
[ "$STATUS" = "disconnected" ] && exit 0

EDID_BIN=
if fw_printenv -n boot_fdt_overlay 2>/dev/null | grep -q yes &&
   fw_printenv -n fdt_overlay_files 2>/dev/null | grep -q 4k; then
    for f in /lib/firmware/edid/*4k*.bin; do
        [ -r "$f" ] && EDID_BIN=$f && break
    done
    if [ -z "$EDID_BIN" ]; then
        logger -t edid-fallback "HDMI-A-1: no EDID on a 4k-configured system and no 4k fallback EDID, waiting for native recovery"
        exit 0
    fi
else
    for f in /lib/firmware/edid/*.bin; do
        case "$f" in *4k*) continue ;; esac
        [ -r "$f" ] && EDID_BIN=$f && break
    done
fi
[ -n "$EDID_BIN" ] || exit 0

cat "$EDID_BIN" > "$OVERRIDE" 2>/dev/null
echo on > "$CONN/status" 2>/dev/null
logger -t edid-fallback "HDMI-A-1: no EDID readable after retries, injected $EDID_BIN"
exit 0

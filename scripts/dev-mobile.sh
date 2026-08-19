#!/usr/bin/env bash
# Run the mobile shell inside a nested niri (winit backend), so mobile layout
# work does not need a phone or a spare TTY.
#
# Usage: scripts/dev-mobile.sh [-s WIDTHxHEIGHT] [-- extra qs args]
#
# Mod+Shift+E quits the nested compositor. Mod+Return opens a terminal inside
# it, which is handy for checking window rules and the top bar.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIRI_CONFIG="$REPO_ROOT/scripts/dev-mobile-niri.kdl"
SIZE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -s | --size)
            SIZE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h | --help)
            sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "WAYLAND_DISPLAY is not set: the winit backend needs a host Wayland session." >&2
    exit 1
fi

for cmd in niri qs; do
    command -v "$cmd" >/dev/null || {
        echo "$cmd not found in PATH" >&2
        exit 1
    }
done

if [ ! -e "$REPO_ROOT/quickshell/DankCommon/Widgets/DankIcon.qml" ]; then
    echo "DankCommon missing: run git submodule update --init" >&2
    exit 1
fi

# The nested compositor is not the session compositor, so --session must stay
# off: it would export this instance's WAYLAND_DISPLAY to systemd and D-Bus and
# hijack the outer session.
if [ -n "$SIZE" ]; then
    # niri only reads the output mode from the config file, so a size override
    # goes through a temporary copy of it.
    TMP_CONFIG="$(mktemp -t dms-mobile-niri-XXXXXX.kdl)"
    trap 'rm -f "$TMP_CONFIG"' EXIT
    sed "s/^    mode \".*\"$/    mode \"$SIZE\"/" "$NIRI_CONFIG" >"$TMP_CONFIG"
    NIRI_CONFIG="$TMP_CONFIG"
fi

# Niri does not forward a startup command's output to its own stdout, so the
# shell logs go to a file the script names up front.
LOG_FILE="${TMPDIR:-/tmp}/dms-mobile.log"
echo "shell log: $LOG_FILE"

QS_CMD="qs -p $(printf '%q' "$REPO_ROOT/quickshell")"
for arg in "$@"; do
    QS_CMD="$QS_CMD $(printf '%q' "$arg")"
done

exec niri -c "$NIRI_CONFIG" -- sh -c "$QS_CMD >$(printf '%q' "$LOG_FILE") 2>&1"

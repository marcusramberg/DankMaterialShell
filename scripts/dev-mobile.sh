#!/usr/bin/env bash
# Run the mobile shell in a nested niri (winit backend).
#
# Usage: scripts/dev-mobile.sh [-s WIDTHxHEIGHT] [-- extra qs args]
#
# Mod+Shift+E quits it, Mod+Return opens a terminal inside it.

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
            sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
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

# No --session: it would hijack the outer session's systemd and D-Bus env.
if [ -n "$SIZE" ]; then
    # niri reads the mode from the config file only.
    TMP_CONFIG="$(mktemp -t dms-mobile-niri-XXXXXX.kdl)"
    trap 'rm -f "$TMP_CONFIG"' EXIT
    sed "s/^    mode \".*\"$/    mode \"$SIZE\"/" "$NIRI_CONFIG" >"$TMP_CONFIG"
    NIRI_CONFIG="$TMP_CONFIG"
fi

# niri does not forward a startup command's output.
LOG_FILE="${TMPDIR:-/tmp}/dms-mobile.log"
echo "shell log: $LOG_FILE"

QS_CMD="qs -p $(printf '%q' "$REPO_ROOT/quickshell")"
for arg in "$@"; do
    QS_CMD="$QS_CMD $(printf '%q' "$arg")"
done

exec niri -c "$NIRI_CONFIG" -- sh -c "$QS_CMD >$(printf '%q' "$LOG_FILE") 2>&1"

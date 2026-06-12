#!/usr/bin/env bash
# Capture window previews on Hyprland using grim region capture.
# Only windows on currently visible workspaces can be captured; the QML side
# (WindowPreviewService) pre-filters the requested addresses accordingly.
#
# Usage: capture-windows-hypr.sh [--all] [0xADDRESS...]

preview_dir="$HOME/.cache/inir/window-previews"

hyprctl_bin=/usr/bin/hyprctl
jq_bin=/usr/bin/jq
grim_bin=/usr/bin/grim

for bin in "$hyprctl_bin" "$jq_bin" "$grim_bin"; do
    if [ ! -x "$bin" ]; then
        echo "[capture-windows-hypr] missing: $bin" 1>&2
        exit 127
    fi
done

declare -a requested
for arg in "$@"; do
    case "$arg" in
        --all) ;; # ids are always passed explicitly; nothing extra to do
        0x*) requested+=("$arg") ;;
    esac
done

[ ${#requested[@]} -eq 0 ] && exit 0

clients=$("$hyprctl_bin" clients -j) || exit 1

mkdir -p "$preview_dir"

count=0
for addr in "${requested[@]}"; do
    geom=$("$jq_bin" -r --arg a "$addr" \
        '.[] | select(.address == $a and .mapped == true and .hidden == false)
             | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' <<<"$clients")
    [ -z "$geom" ] && continue

    "$grim_bin" -g "$geom" "$preview_dir/window-$addr.png" 2>/dev/null &

    count=$((count + 1))
    if [ $((count % 4)) -eq 0 ]; then
        wait
    fi
done
wait

exit 0

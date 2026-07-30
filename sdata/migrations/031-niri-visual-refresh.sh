#!/usr/bin/env bash
# Migration: Niri visual refresh (animations, focus ring, shadows, corner radius)
#
# Applies the 2.27 compositor polish to existing installs:
#   - 60-animations.kdl: crafted per-interaction springs (overshoot on open,
#     clean fade on close, critically damped direct manipulation)
#   - 20-layout-and-overview.kdl: focus ring enabled (themed via the already
#     generated 99-generated-colors.kdl), softer window shadow
#   - 30-window-rules.kdl: corner radius 18 (matches shell), gentler 0.95 dim
#
# Only files that still match the PREVIOUS shipped defaults are replaced —
# anything the user customized is left alone.

MIGRATION_ID="031-niri-visual-refresh"
MIGRATION_TITLE="Niri visual refresh (animations, focus ring, shadows)"
MIGRATION_DESCRIPTION="Updates uncustomized niri config.d files to the 2.27 defaults: crafted animation springs, themed focus ring (enabled), softer shadows, corner radius 18, gentler inactive dim. Customized files are preserved."
MIGRATION_REQUIRED=false

_niri_config_dir() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/niri"
}

_repo_root() {
  echo "${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)}"
}

# sha256 of the previous shipped defaults (pre-2.27)
_old_hash() {
  case "$1" in
    20-layout-and-overview) echo "09562d5a5277de9b88bada9fe571733ca87a8b0c709025f1d480877088188fb8" ;;
    30-window-rules)        echo "ecff4a43e818a3b1c738ba5970cfdcfa67598aa9b1a4d188c1ad6b7def1b5b8e" ;;
    60-animations)          echo "fe80cc9d3027e0990c1a9250fad5acdbc8fcffb956c81eaf9ddb004a71f114f7" ;;
  esac
}

_file_matches_old_default() {
  local file="$1" name="$2"
  [[ -f "$file" ]] || return 1
  local sum
  sum=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
  [[ "$sum" == "$(_old_hash "$name")" ]]
}

migration_check() {
  local niri_dir
  niri_dir="$(_niri_config_dir)"
  [[ -d "$niri_dir/config.d" ]] || return 1

  local name
  for name in 20-layout-and-overview 30-window-rules 60-animations; do
    local file="$niri_dir/config.d/$name.kdl"
    # Needs migration if the file is missing or still the old default
    if [[ ! -f "$file" ]] || _file_matches_old_default "$file" "$name"; then
      return 0
    fi
  done
  return 1
}

migration_apply() {
  local niri_dir repo_root
  niri_dir="$(_niri_config_dir)"
  repo_root="$(_repo_root)"
  [[ -d "$niri_dir/config.d" ]] || return 0
  [[ -d "$repo_root/defaults/niri/config.d" ]] || return 0

  local name changed=0
  for name in 20-layout-and-overview 30-window-rules 60-animations; do
    local file="$niri_dir/config.d/$name.kdl"
    local new_default="$repo_root/defaults/niri/config.d/$name.kdl"

    if [[ ! -f "$file" ]]; then
      # Missing file — install the new default
      cp "$new_default" "$file"
      changed=1
      continue
    fi

    if _file_matches_old_default "$file" "$name"; then
      # Untouched previous default — back up, then replace
      cp "$file" "$file.bak-mig031"
      cp "$new_default" "$file"
      changed=1
    fi
    # Anything else = user customized → preserve
  done

  # Reload the compositor if it's running (harmless otherwise)
  if [[ "$changed" -eq 1 ]] && command -v niri >/dev/null 2>&1 && [[ -n "${NIRI_SOCKET:-}" ]]; then
    niri msg action reload-config >/dev/null 2>&1 || true
  fi
}

migration_preview() {
  echo "For niri config.d files that still match the previous shipped defaults:"
  echo "  - 60-animations.kdl: crafted springs (overshoot open, 150ms fade close,"
  echo "    critically damped move/resize)"
  echo "  - 20-layout-and-overview.kdl: focus ring ON (width 2, themed via the"
  echo "    wallpaper-generated colors file), softer shadow (45/2/y6)"
  echo "  - 30-window-rules.kdl: corner radius 18, inactive opacity 0.95"
  echo ""
  echo "Files you customized are left untouched. Replaced files are backed up"
  echo "as *.bak-mig031. The focus-ring gradient appears on the next wallpaper"
  echo "or theme apply (the colors file is re-rendered then)."
}

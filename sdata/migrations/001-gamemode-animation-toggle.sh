# Migration: Add //off to Niri animations block for GameMode support
# This allows iNiR to toggle animations on/off for gaming
#
# GameMode toggles compositor animations by flipping a marker line inside the
# animations block between `//off` (commented, animations on) and `off`
# (uncommented, animations off) with sed. Without that marker line present it has
# nothing to flip and silently does nothing.
#
# This migration used to look only at ~/.config/niri/config.kdl. Since the config
# was split into config.d/, the animations block lives in
# config.d/60-animations.kdl and config.kdl only holds includes — so the check
# always reported "needed" while the apply found no animations block and did
# nothing, leaving the migration permanently pending and GameMode unable to
# disable animations. It now resolves whichever file actually holds the block.

MIGRATION_ID="001-gamemode-animation-toggle"
MIGRATION_TITLE="GameMode Animation Toggle"
MIGRATION_DESCRIPTION="Adds the //off marker to Niri's animations block so iNiR can
  toggle animations off when GameMode activates. Works with both the modular
  config.d layout and a single-file config.kdl. Without it GameMode silently
  leaves animations running."
MIGRATION_REQUIRED=false

# Resolve the file that actually contains the top-level `animations {` block:
# the modular config.d file first, then a single-file config.kdl.
_animations_file() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
  local candidate
  for candidate in "$dir/config.d/60-animations.kdl" "$dir/config.kdl"; do
    [[ -f "$candidate" ]] || continue
    if grep -qE '^animations[[:space:]]*\{' "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# The marker line, commented or not, on its own line inside the block.
_has_marker() {
  grep -qE '^[[:space:]]*(//)?off[[:space:]]*$' "$1"
}

migration_check() {
  local file
  file="$(_animations_file)" || return 1
  ! _has_marker "$file"
}

migration_preview() {
  local file
  if ! file="$(_animations_file)"; then
    echo "  No file with a top-level 'animations {' block found — nothing to do."
    return 0
  fi
  echo -e "${STY_GREEN}+ //off${STY_RST}  (first line inside the animations { } block)"
  echo ""
  echo "  File: $file"
  echo "  The line stays commented, so animations are unaffected until GameMode"
  echo "  activates and uncomments it."
}

migration_diff() {
  local file
  if ! file="$(_animations_file)"; then
    echo "No animations block found."
    return 0
  fi
  echo "File: $file"
  echo ""
  echo "Before:"
  grep -A2 -E '^animations[[:space:]]*\{' "$file" 2>/dev/null | head -4
  echo ""
  echo "After:"
  echo "animations {"
  echo "    //off"
  echo "    ..."
}

migration_apply() {
  local file
  file="$(_animations_file)" || return 0
  _has_marker "$file" && return 0

  # Insert the marker as the first line inside the block. sed is enough here and
  # avoids rewriting the rest of a file the user may have customized heavily.
  sed -i '0,/^animations[[:space:]]*{/s//animations {\n    \/\/off/' "$file" || return 1

  _has_marker "$file"
}

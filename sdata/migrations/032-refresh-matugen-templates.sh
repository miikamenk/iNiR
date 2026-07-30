#!/usr/bin/env bash
# Migration: Refresh ~/.config/matugen theming templates
#
# The theming templates live outside the shell payload, in ~/.config/matugen, and
# used to be installed only by `./setup install`. `./setup update` never re-synced
# them, so any install that was updated rather than reinstalled kept rendering
# from whatever templates existed at first install:
#
#   - templates.json (the current manifest) never appeared, so the renderer fell
#     back to the legacy config.toml, which lists only the original 8 templates.
#   - Templates added since — niri focus ring, nvim, firefox, steam, fish —
#     were absent entirely and therefore never rendered.
#
# The visible symptom is consumers frozen on an old wallpaper's colours: the niri
# focus ring, Neovim and fish stay the same however the wallpaper changes, while
# the shell itself themes correctly (it reads the palette directly).
#
# `./setup update` now performs this sync too; this migration is for installs
# that predate that change. Copies in shipped templates without --delete, so
# templates the user added themselves survive.

MIGRATION_ID="032-refresh-matugen-templates"
MIGRATION_TITLE="Refresh theming templates (fixes focus ring / Neovim / fish colours)"
MIGRATION_DESCRIPTION="Re-syncs ~/.config/matugen from the current checkout. Adds the templates.json manifest and the templates added since your install (niri focus ring, Neovim, fish, firefox, steam), so those consumers follow the wallpaper again instead of staying on old colours. Templates you added yourself are preserved."
MIGRATION_REQUIRED=false

_matugen_dir() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/matugen"
}

_repo_root() {
  echo "${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)}"
}

_source_dir() {
  echo "$(_repo_root)/defaults/matugen"
}

migration_check() {
  local src dst
  src="$(_source_dir)"
  dst="$(_matugen_dir)"
  [[ -d "$src" ]] || return 1
  # Nothing to do if matugen was never set up — a fresh install handles it.
  [[ -d "$dst" ]] || return 1

  # Needed when the manifest is missing (renderer still on legacy config.toml)...
  [[ -f "${dst}/templates.json" ]] || return 0

  # ...or when any shipped template is absent from the user's copy.
  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -f "${dst}/${rel}" ]] || return 0
  done < <(cd "$src" && find . -type f -not -name 'AGENTS.md' -printf '%P\n' 2>/dev/null)

  return 1
}

migration_apply() {
  local src dst
  src="$(_source_dir)"
  dst="$(_matugen_dir)"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"

  # No --delete: preserve anything the user added.
  rsync -a --exclude='AGENTS.md' "${src}/" "${dst}/" || return 1

  # config.toml is intentionally left in place. It ships in defaults/matugen, so
  # removing it here would only invite it back on the next sync, and the renderer
  # ignores it whenever templates.json exists.
  return 0
}

migration_preview() {
  local src dst
  src="$(_source_dir)"
  dst="$(_matugen_dir)"
  echo "Sync $src -> $dst (no deletions)."
  echo ""
  if [[ ! -f "${dst}/templates.json" ]]; then
    echo "  + templates.json — the current manifest. Without it the renderer"
    echo "    falls back to the legacy config.toml and ignores newer templates."
  fi
  local rel missing=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if [[ ! -f "${dst}/${rel}" ]]; then
      echo "  + ${rel}"
      missing=$((missing + 1))
    fi
  done < <(cd "$src" && find . -type f -not -name 'AGENTS.md' -printf '%P\n' 2>/dev/null | sort)
  [[ "$missing" -eq 0 ]] && echo "  (all shipped templates already present; manifest refresh only)"
  echo ""
  echo "Once templates.json is present the renderer uses it and ignores the"
  echo "legacy config.toml, which is left in place."
  echo "Colours re-render on the next wallpaper or theme apply."
}

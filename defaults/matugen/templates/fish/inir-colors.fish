# iNiR Material You fish colors
# Rendered by iNiR's unified wallpaper-color pipeline — do not edit by hand.
#
# Lands in ~/.config/fish/conf.d/. Files there are sourced in alphabetical order,
# so this sorts after fish's own `fish_frozen_theme.fish` (f < i) and its
# --global assignments win. Global also beats universal scope, so this overrides
# both the frozen theme and any older `set -U fish_color_*` values.

# ── Syntax highlighting ──
set --global fish_color_normal {{colors.on_surface.default.hex_stripped}}
set --global fish_color_command {{colors.primary.default.hex_stripped}}
set --global fish_color_keyword {{colors.tertiary.default.hex_stripped}}
set --global fish_color_quote {{colors.success.default.hex_stripped}}
set --global fish_color_redirection {{colors.secondary.default.hex_stripped}}
set --global fish_color_end {{colors.tertiary.default.hex_stripped}}
set --global fish_color_error {{colors.error.default.hex_stripped}}
set --global fish_color_param {{colors.on_surface_variant.default.hex_stripped}}
set --global fish_color_option {{colors.secondary.default.hex_stripped}}
set --global fish_color_comment {{colors.outline.default.hex_stripped}}
set --global fish_color_operator {{colors.tertiary.default.hex_stripped}}
set --global fish_color_escape {{colors.secondary.default.hex_stripped}}
set --global fish_color_autosuggestion {{colors.outline_variant.default.hex_stripped}}
set --global fish_color_cancel {{colors.error.default.hex_stripped}}
set --global fish_color_valid_path --underline

# ── Selection & search ──
set --global fish_color_selection {{colors.on_surface.default.hex_stripped}} --background={{colors.surface_variant.default.hex_stripped}}
set --global fish_color_search_match --background={{colors.surface_container_high.default.hex_stripped}}
set --global fish_color_history_current {{colors.primary.default.hex_stripped}} --bold

# ── Prompt ──
set --global fish_color_cwd {{colors.primary.default.hex_stripped}}
set --global fish_color_cwd_root {{colors.error.default.hex_stripped}}
set --global fish_color_user {{colors.tertiary.default.hex_stripped}}
set --global fish_color_host {{colors.primary.default.hex_stripped}}
set --global fish_color_host_remote {{colors.tertiary.default.hex_stripped}}
set --global fish_color_status {{colors.error.default.hex_stripped}}

# ── Completion pager ──
set --global fish_pager_color_prefix {{colors.primary.default.hex_stripped}} --bold
set --global fish_pager_color_completion {{colors.on_surface.default.hex_stripped}}
set --global fish_pager_color_description {{colors.outline.default.hex_stripped}}
set --global fish_pager_color_progress {{colors.on_surface_variant.default.hex_stripped}} --background={{colors.surface_container.default.hex_stripped}}
set --global fish_pager_color_selected_background --background={{colors.surface_variant.default.hex_stripped}}
set --global fish_pager_color_selected_prefix {{colors.primary.default.hex_stripped}} --bold
set --global fish_pager_color_selected_completion {{colors.on_surface.default.hex_stripped}}
set --global fish_pager_color_selected_description {{colors.on_surface_variant.default.hex_stripped}}

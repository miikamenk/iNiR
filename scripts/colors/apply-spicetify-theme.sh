#!/usr/bin/env bash
#
# apply-spicetify-theme.sh - Generate and apply a Spicetify color scheme
# from iNiR Material colors using the Sleek theme with live updates.
#
# Reads:  ~/.local/state/quickshell/user/generated/colors.json
# Writes: ~/.config/spicetify/Themes/Sleek/color.ini

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
COLORS_JSON="$STATE_DIR/user/generated/colors.json"
LOG_FILE="$STATE_DIR/user/generated/spicetify_theme.log"

THEME_NAME="Sleek"
SCHEME_NAME="matugen"

mkdir -p "$STATE_DIR/user/generated" 2>/dev/null || true
if ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="/tmp/ii_spicetify_theme.log"
  touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
fi

log() {
  [[ -n "$LOG_FILE" ]] || return 0
  printf "[spicetify] %s\n" "$*" | tee -a "$LOG_FILE" >/dev/null 2>&1 || true
}

strip_hash() {
  local color="$1"
  color="${color#\#}"
  echo "${color,,}"
}

if ! command -v spicetify &>/dev/null; then
  log "spicetify not installed. Skipping."
  exit 0
fi

if [[ ! -f "$COLORS_JSON" ]] || ! command -v jq &>/dev/null; then
  log "colors.json missing or jq unavailable. Skipping."
  exit 0
fi

primary=$(jq -r '.primary // "#8caaee"' "$COLORS_JSON")
on_surface=$(jq -r '.on_surface // "#dce0e8"' "$COLORS_JSON")
on_surface_variant=$(jq -r '.on_surface_variant // "#a6adc8"' "$COLORS_JSON")
surface=$(jq -r '.surface // "#1e1e2e"' "$COLORS_JSON")
surface_container_low=$(jq -r '.surface_container_low // "#181825"' "$COLORS_JSON")
surface_container=$(jq -r '.surface_container // "#313244"' "$COLORS_JSON")
surface_container_high=$(jq -r '.surface_container_high // "#45475a"' "$COLORS_JSON")
primary_container=$(jq -r '.primary_container // "#313244"' "$COLORS_JSON")
secondary=$(jq -r '.secondary // "#89b4fa"' "$COLORS_JSON")
tertiary=$(jq -r '.tertiary // "#94e2d5"' "$COLORS_JSON")
outline=$(jq -r '.outline // "#585b70"' "$COLORS_JSON")
outline_variant=$(jq -r '.outline_variant // "#45475a"' "$COLORS_JSON")
error=$(jq -r '.error // "#f38ba8"' "$COLORS_JSON")
shadow=$(jq -r '.shadow // "#000000"' "$COLORS_JSON")

spicetify_config="${SPICETIFY_CONFIG_PATH:-$XDG_CONFIG_HOME/spicetify/config-xpui.ini}"
if cmd_config=$(spicetify -c 2>/dev/null); then
  [[ -n "$cmd_config" ]] && spicetify_config="$cmd_config"
fi
spicetify_root="$(dirname "$spicetify_config")"
theme_dir="$spicetify_root/Themes/$THEME_NAME"
color_file="$theme_dir/color.ini"
user_css_file="$theme_dir/user.css"
config_file="$spicetify_root/config-xpui.ini"
watch_pid_file="$STATE_DIR/user/generated/spicetify_watch.pid"

if ! mkdir -p "$theme_dir" 2>/dev/null; then
  log "Cannot create theme directory: $theme_dir"
  exit 1
fi

if [[ ! -f "$user_css_file" ]]; then
  if ! curl -L --create-dirs -o "$user_css_file" \
    "https://raw.githubusercontent.com/spicetify/spicetify-themes/master/Sleek/user.css" 2>>"$LOG_FILE"; then
    log "Failed to download Sleek user.css."
  fi
fi

if ! cat > "$color_file" <<EOF
[${SCHEME_NAME}]
text               = $(strip_hash "$on_surface")
subtext            = $(strip_hash "$on_surface_variant")
main               = $(strip_hash "$surface")
sidebar            = $(strip_hash "$surface_container_low")
player             = $(strip_hash "$surface_container")
card               = $(strip_hash "$surface_container_high")
shadow             = $(strip_hash "$shadow")
selected-row       = $(strip_hash "$primary_container")
button             = $(strip_hash "$primary")
button-active      = $(strip_hash "$secondary")
button-disabled    = $(strip_hash "$outline")
tab-active         = $(strip_hash "$primary_container")
notification       = $(strip_hash "$tertiary")
notification-error = $(strip_hash "$error")
misc               = $(strip_hash "$outline_variant")
EOF
then
  log "Cannot write color scheme file: $color_file"
  exit 1
fi

spicetify config inject_css 1 replace_colors 1 >> "$LOG_FILE" 2>&1 || true
spicetify config current_theme "$THEME_NAME" color_scheme "$SCHEME_NAME" >> "$LOG_FILE" 2>&1 || true

spotify_running=$(pgrep -x spotify 2>/dev/null)
watch_running=false

if [[ -f "$watch_pid_file" ]]; then
  watch_pid=$(cat "$watch_pid_file" 2>/dev/null)
  if [[ -n "$watch_pid" ]] && kill -0 "$watch_pid" 2>/dev/null; then
    watch_running=true
  fi
fi

if ! $watch_running && pgrep -f "spicetify watch" >/dev/null 2>&1; then
  watch_running=true
fi

if [[ -n "$spotify_running" ]] || $watch_running; then
  log "Spotify/watcher already running - color.ini updated, live reload will handle it."
  log "Updated colors: primary=$(strip_hash "$primary"), surface=$(strip_hash "$surface")"
  exit 0
fi

log "Initial setup - running spicetify apply and starting watch mode."

apply_out=""
if ! apply_out=$(spicetify apply 2>&1); then
  printf "%s\n" "$apply_out" >> "$LOG_FILE" 2>&1
  if printf "%s" "$apply_out" | grep -Eqi "backup|cannot find backup|run.*backup"; then
    log "Detected missing/invalid backup. Running 'spicetify backup apply'."
    if ! backup_out=$(spicetify backup apply 2>&1); then
      printf "%s\n" "$backup_out" >> "$LOG_FILE" 2>&1
      log "spicetify backup apply failed."
      exit 1
    fi
    printf "%s\n" "$backup_out" >> "$LOG_FILE" 2>&1
  else
    log "spicetify apply failed."
    exit 1
  fi
else
  printf "%s\n" "$apply_out" >> "$LOG_FILE" 2>&1
fi

log "Applied theme '$THEME_NAME' (scheme '$SCHEME_NAME'). Starting watch mode."

exec spicetify watch -s 2>&1 | sed "/Reloaded Spotify/q" &
watch_pid=$!
echo "$watch_pid" > "$watch_pid_file"

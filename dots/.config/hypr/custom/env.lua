-- Overrides for ~/.config/hypr/hyprland/env.lua
-- This file will not be overwritten across dots-hyprland updates.

-- inir scripts prefer INIR_VENV, falling back to ILLOGICAL_IMPULSE_VIRTUAL_ENV
-- (which hyprland/env.lua already sets to the same path). Set here too so both
-- are defined, matching ~/.config/niri/config.d/40-environment.kdl.
hl.env("INIR_VENV", HOME .. "/.local/state/quickshell/.venv")

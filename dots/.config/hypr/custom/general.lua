hl.config({
	general = {
		gaps_in = 5, -- niri `gaps 10` ≈ ~10px between windows (gaps_in is per side)
		gaps_out = 10,
		border_size = 2, -- niri focus-ring width 1.5 — border_size is whole pixels, so 2 is closest
		-- Focus/border colors are controlled by matugen via hyprland/colors.lua
		-- (generated from ~/.config/matugen/templates/hyprland/colors.lua).
	},
	input = {
		kb_layout = "fi",
		numlock_by_default = true,
		repeat_delay = 250,
		repeat_rate = 35,

		follow_mouse = 1, -- focus-follows-mouse

		-- mouse acceleration (niri mouse block)
		accel_profile = "flat", -- accel-profile "flat"
		sensitivity = -0.4, -- accel-speed -0.4  (range -1.0..1.0)
		scroll_factor = 2.0, -- mouse scroll-factor 2.0

		touchpad = {
			natural_scroll = true,
		},

		-- niri tablet/touch map-to-output → per-category output
		tablet = {
			output = "DP-3",
		},
		touchdevice = {
			output = "HDMI-A-1",
		},
	},
	cursor = {
		hide_on_key_press = true,
	},
	scrolling = {
		column_width = 0.5,
	},
})

-- Curves
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } }) -- niri ease-out-expo
hl.curve("easeOutQuad", { type = "bezier", points = { { 0.25, 0.46 }, { 0.45, 0.94 } } }) -- niri ease-out-quad
hl.curve("wsSpring", { type = "spring", mass = 1, stiffness = 80, dampening = 17 }) -- was 250 / 25
hl.curve("moveSpring", { type = "spring", mass = 1, stiffness = 80, dampening = 21 }) -- was 300 / 33

-- Animations (speed is in deciseconds: 1 = 100ms)
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "easeOutExpo", style = "popin 80%" }) -- 200ms
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.5, bezier = "easeOutQuad", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, spring = "moveSpring" }) -- was speed 4
hl.animation({ leaf = "workspaces", enabled = true, speed = 7, spring = "wsSpring" }) -- was speed 5
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "easeOutQuad" }) -- snappy fades

-- Monitors
hl.monitor({
	output = "DP-2",
	mode = "2560x1440@119.998",
	position = "670x-1440",
	scale = 1,
	vrr = 1, -- 1 = always on, niri's plain "variable-refresh-rate" maps to this
})

hl.monitor({
	output = "HDMI-A-1",
	mode = "3840x2160@120.000",
	position = "0x0",
	scale = 1,
	bitdepth = 10,
	supports_hdr = 1,
	vrr = 2, -- 2 = on-demand, matches niri's on-demand=true
})

hl.workspace_rule({ workspace = "1", monitor = "HDMI-A-1", layout = "scrolling", default = true }) -- Main
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1" }) -- Game (dwindle)
hl.workspace_rule({ workspace = "5", monitor = "HDMI-A-1", layout = "scrolling" }) -- Code
-- DP-2 group:
hl.workspace_rule({ workspace = "3", monitor = "DP-2", layout = "scrolling", default = true }) -- Social
hl.workspace_rule({ workspace = "4", monitor = "DP-2" }) -- Misc (dwindle)
hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1" }) -- Info

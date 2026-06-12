--------------------------------
---- WINDOW → WORKSPACE RULES ---
--------------------------------
-- 'silent' = open on that workspace WITHOUT switching focus to it,
-- which mirrors niri's open-on-workspace. Drop " silent" if you want focus to follow.

-- Social (DP-2)
hl.window_rule({
	name = "steam-social",
	match = { class = "^([Ss]team)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "steamhelper-social",
	match = { class = "^(steamwebhelper)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "discord-social",
	match = { class = "^(discord)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "vesktop-social",
	match = { class = "^vesktop$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "spotify-social",
	match = { class = "^([Ss]potify)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "spotify-free-social",
	match = { title = "^(Spotify Free)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})
hl.window_rule({
	name = "spotify-prem-social",
	match = { title = "^(Spotify Premium)$" },
	workspace = "3 silent",
	scrolling_width = 0.33,
})

-- Misc (DP-2)
hl.window_rule({
	name = "easyeffects-misc",
	match = { class = "^(org\\.kde\\.easyeffects)$" },
	workspace = "4 silent",
})

-- Info (HDMI-A-1)
hl.window_rule({ name = "tidal-info", match = { class = "^(tidal-hifi)$" }, workspace = "name:Info silent" })
hl.window_rule({
	name = "minimedia-info",
	match = { class = "^(minimedia)$" },
	workspace = "name:Info silent",
	fullscreen = true,
})

-- KeePassXC → special (scratchpad), floating
hl.window_rule({
	name = "keepassxc-scratch",
	match = { title = "^(.+ KeePassXC)$" },
	workspace = "special",
	float = true,
})

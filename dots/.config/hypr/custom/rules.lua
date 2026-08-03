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

-- Liquid glass (hyprglass plugin, see custom/plugins.lua): only glass
-- non-focused, non-fullscreen windows. `+tag` via window_rule only ever
-- *adds* hyprglass_disabled when the match turns true — it does not clear it
-- again when the match later turns false — so each focus/fullscreen combo
-- needs its own explicit rule (all four are mutually exclusive, so order
-- between them doesn't matter).
hl.window_rule({ name = "liquidglass-off-1", match = { focus = false, fullscreen = false }, tag = "-hyprglass_disabled" })
hl.window_rule({ name = "liquidglass-off-2", match = { focus = false, fullscreen = true }, tag = "+hyprglass_disabled" })
hl.window_rule({ name = "liquidglass-off-3", match = { focus = true, fullscreen = false }, tag = "+hyprglass_disabled" })
hl.window_rule({ name = "liquidglass-off-4", match = { focus = true, fullscreen = true }, tag = "+hyprglass_disabled" })

-- Never glass PiP / screen-share indicator windows either, even while
-- unfocused — they should stay clearly visible no matter what has focus.
hl.window_rule({
	name = "liquidglass-exclude-pip",
	match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
	tag = "+hyprglass_disabled",
})
hl.window_rule({
	name = "liquidglass-exclude-screenshare",
	match = { title = ".*is sharing (a window|your screen).*" },
	tag = "+hyprglass_disabled",
})

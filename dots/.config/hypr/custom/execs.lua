-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
	hl.exec_cmd("~/.config/onedrive-sync.sh")
	hl.exec_cmd("keepassxc")
	hl.exec_cmd("vesktop")
	hl.exec_cmd("steam")
	hl.exec_cmd("spotify-launcher")
	hl.exec_cmd("flatpak run com.core447.StreamController -b")
	hl.exec_cmd("fcitx5")
	hl.exec_cmd("flatpak run com.github.wwmm.easyeffects")
	hl.exec_cmd("kded6")

	-- bash -c wrappers from niri aren't needed; exec_cmd already runs via a shell.

	-- Dexcom HID bridge — uses $(...) substitution, so keep the sh -c wrapper.
	-- [[ ]] is a Lua long string, so the inner double quotes don't need escaping.
	hl.exec_cmd(
		[[sh -c "/home/menk/Projects/qmk/qmk_userspace/tools/.venv/bin/python3 /home/menk/Projects/qmk/qmk_userspace/tools/dexcom_g7_hid.py --username $(secret-tool lookup service dexcom key username) --password $(secret-tool lookup service dexcom key password) --region ous"]]
	)

	-- DROPPED: ~/.config/niri/group-windows.sh — niri-specific, won't work in Hyprland.
	-- Use Hyprland window rules (hl.window_rule) for grouping behavior instead.

	-- DROPPED: xrandr --output HDMI-A-1 --primary — xrandr is X11-only, no effect on Wayland.
	-- Configure the monitor (and "primary" positioning) via hl.monitor instead, e.g.:
	--   hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "0x0", scale = "auto" })
end)

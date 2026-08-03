-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function()
	hl.exec_cmd("systemctl --user start hyprland-session.target")
	-- Bar, wallpaper
	-- The "hyprland.start" hook re-fires on every `hyprctl reload` (and
	-- Hyprland auto-reloads whenever a config file changes), so every long-
	-- running launch here needs an already-running guard or reloads stack
	-- duplicate instances.
	--
	-- For quickshell use its own -n/--no-duplicate rather than a pgrep guard:
	-- the running shell re-execs itself, so its command line is a bare
	-- "/usr/bin/quickshell" and never matches a pattern like "qs -c inir".
	--
	-- QS_DISABLE_CRASH_HANDLER: quickshell 0.3.0 segfaults during engine
	-- teardown (use-after-free in IpcHandlerRegistry, see
	-- patches/quickshell/fix-extension-uaf.patch), which happens on every hot
	-- reload. With the crash handler on, each crash leaves a forked copy alive
	-- that still holds its layer-shell surfaces — visible as a duplicate bar
	-- that cannot be closed. inir.service already sets this; the Hyprland exec
	-- path needs it too, since inir.service is only wired for niri.
	hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
	hl.exec_cmd("QS_DISABLE_CRASH_HANDLER=1 qs -n -c $qsConfig")
	hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

	-- Core components (authentication, lock screen, notification daemon)
	hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
	hl.exec_cmd("pgrep -x hypridle > /dev/null || hypridle")
	hl.exec_cmd("dbus-update-activation-environment --all")
	hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk

	-- Audio

	-- Clipboard: history
	--hl.exec_cmd("wl-paste --watch cliphist store")
	-- [b]racketed first letter so the pattern doesn't match its own sh wrapper
	hl.exec_cmd(
		"pgrep -f 'wl-paste --type [t]ext --watch' > /dev/null || wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'"
	)
	hl.exec_cmd(
		"pgrep -f 'wl-paste --type [i]mage --watch' > /dev/null || wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'"
	)

	-- Cursor
	hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)

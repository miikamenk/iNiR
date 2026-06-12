local qsIpcCall = "qs -c $qsConfig ipc call"
local hyprScripts = "$HOME/.config/hypr/hyprland/scripts"

hl.bind(
	"CTRL+SUPER+ALT+Slash",
	hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
	{ description = "Edit user keybinds" }
)

------------------------------------------------------------
-- Disable defaults we don't want / are about to remap
------------------------------------------------------------
hl.unbind("SUPER + SUPER_L") -- default: searchToggleRelease
hl.unbind("SUPER + SUPER_R") -- default: searchToggleRelease
hl.unbind("SUPER + A") -- default: sidebarLeftToggle       -> overview
hl.unbind("SUPER + ALT + A") -- default: sidebarLeftToggleDetach -> moved to ALT+O
hl.unbind("SUPER + J") -- default: barToggle               -> togglesplit
hl.unbind("SUPER + Slash") -- default: cheatsheetToggle         -> moved to SUPER+Plus
hl.unbind("SUPER + B") -- default: sidebarLeftToggle       -> browser
hl.unbind("SUPER + C") -- default: codeEditor              -> your launcher
hl.unbind("SUPER + Apostrophe") -- default: splitratio +0.1         -> barToggle
hl.unbind("SUPER + ALT + R") -- default: regionRecord            -> layout switch
hl.unbind("CTRL + ALT + R") -- default: record fullscreen        -> disabled
hl.unbind("SUPER + SHIFT + ALT + R") -- default: record with sound        -> disabled
hl.unbind("CTRL + SUPER + Left") -- default: focus workspace left     -> move column left
hl.unbind("CTRL + SUPER + Right") -- default: focus workspace right    -> move column right
-- NEW unbinds for this round:
hl.unbind("SUPER + I") -- default: App: Settings (CONFLICT)  -> focus workspace up
hl.unbind("SUPER + Equal") -- default: screen zoom in (CONFLICT) -> grow column
hl.unbind("SUPER + Minus") -- default: screen zoom out (CONFLICT)-> shrink column
hl.unbind("SUPER + SHIFT + Left") -- default: move window left  (CONFLICT) -> combine into column
hl.unbind("SUPER + SHIFT + Right") -- default: move window right (CONFLICT) -> combine into column
hl.unbind("SUPER + SHIFT + Up") -- default: move window up    (CONFLICT) -> reorder in column
hl.unbind("SUPER + SHIFT + Down") -- default: move window down  (CONFLICT) -> reorder in column
hl.unbind("SUPER + Plus") -- default: move window down  (CONFLICT) -> reorder in column
hl.unbind("SUPER + W") -- default: App: Browser (CONFLICT)  -> toggle floating
-- ii globals that don't exist in the inir shell config; rebound below via IPC
hl.unbind("SUPER + Tab") -- default: overviewWorkspacesToggle  -> ipc overview toggle
hl.unbind("SUPER + V") -- default: overviewClipboardToggle -> ipc clipboard toggle
hl.unbind("SUPER + Period") -- default: overviewEmojiToggle      -> fuzzel emoji picker
hl.unbind("CTRL + SUPER + SHIFT + D") -- default: toggleLightDark      -> gsettings flip + switchwall
hl.unbind("CTRL + SUPER + P") -- default: panelFamilyCycle          -> ipc panelFamily cycle
hl.unbind("SUPER + SHIFT + T") -- default: screenTranslate     -> disabled (no inir equivalent)
hl.unbind("SUPER + F") -- default: Fullscreen -> full column
------------------------------------------------------------
-- Shell / quickshell
------------------------------------------------------------
hl.bind("SUPER + A", hl.dsp.exec_cmd(qsIpcCall .. " overview toggle"), { description = "Toggle overview/launcher" })
hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd(qsIpcCall .. " sidebarLeft detach"))
hl.bind("SUPER + Apostrophe", hl.dsp.global("quickshell:barToggle"), { description = "Toggle bar" })
hl.bind("SUPER + SHIFT + Plus", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Toggle cheatsheet" })

-- inir replacements for ii globals removed above
hl.bind("SUPER + Tab", hl.dsp.exec_cmd(qsIpcCall .. " overview toggle"), { description = "Toggle overview" })
hl.bind(
	"SUPER + V",
	hl.dsp.exec_cmd(
		qsIpcCall
			.. " clipboard toggle || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"
	),
	{ description = "Clipboard history" }
)
hl.bind(
	"SUPER + Period",
	hl.dsp.exec_cmd("pkill fuzzel || " .. hyprScripts .. "/fuzzel-emoji.sh copy"),
	{ description = "Emoji picker" }
)
hl.bind("CTRL + SUPER + P", hl.dsp.exec_cmd(qsIpcCall .. " panelFamily cycle"), { description = "Cycle panel family" })
hl.bind(
	"CTRL + SUPER + SHIFT + D",
	hl.dsp.exec_cmd(
		'[ "$(gsettings get org.gnome.desktop.interface color-scheme)" = "\'prefer-dark\'" ] && mode=light || mode=dark; ~/.config/quickshell/$qsConfig/scripts/colors/switchwall.sh --mode $mode --noswitch'
	),
	{ description = "Toggle light/dark mode" }
)

local saved = {}

hl.bind("SUPER + F", function()
	local w = hl.get_active_window()
	if w == nil then
		return
	end

	if saved[w.address] then
		hl.dispatch(hl.dsp.layout("colresize " .. saved[w.address]))
		saved[w.address] = nil
	else
		local col = w.layout and w.layout.column
		if col == nil then
			return
		end -- floating, or not in the scrolling layout
		saved[w.address] = col.width -- exact column-width fraction
		hl.dispatch(hl.dsp.layout("colresize 1.0"))
	end
end)
hl.bind(
	"SUPER + SHIFT + F",
	hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
	{ description = "Window: Fullscreen" }
)
------------------------------------------------------------
-- Window / layout
------------------------------------------------------------
hl.bind("SUPER + W", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"), { description = "Window Management toggle split" })

-- Column width: cycle through presets (Super+R)
local colWidths = { 0.25, 0.33, 0.5, 0.66, 0.75, 1.0 }

hl.bind("SUPER + R", function()
	local w = hl.get_active_window()
	local col = w ~= nil and w.layout and w.layout.column
	if col == nil then
		return
	end

	-- index of the preset closest to the current column width
	local closest, best = 1, math.huge
	for i, v in ipairs(colWidths) do
		local diff = math.abs(v - col.width)
		if diff < best then
			best, closest = diff, i
		end
	end

	-- step to the next preset up, wrapping past the largest
	local nextIdx = closest % #colWidths + 1
	hl.dispatch(hl.dsp.layout("colresize " .. colWidths[nextIdx]))
end, { description = "Cycle column width preset" })

-- Column width: grow / shrink (Super+= / Super+-)
hl.bind("SUPER + Plus", hl.dsp.layout("colresize +0.1"), { repeating = true, description = "Grow column" })
hl.bind("SUPER + Minus", hl.dsp.layout("colresize -0.1"), { repeating = true, description = "Shrink column" })

-- Scrolling layout: combine windows into a column (Super+Shift+arrow)
-- Combine / expel into the current column (Super+Shift+Left/Right)
hl.bind("SUPER + SHIFT + Left", hl.dsp.layout("consume_or_expel prev"), { description = "Combine into column (prev)" })
hl.bind("SUPER + SHIFT + Right", hl.dsp.layout("consume_or_expel next"), { description = "Combine into column (next)" })

-- Reorder the focused window up/down within its column (Super+Shift+Up/Down)
hl.bind("SUPER + SHIFT + Up", hl.dsp.window.move({ direction = "u" }), { description = "Move window up in column" })
hl.bind("SUPER + SHIFT + Down", hl.dsp.window.move({ direction = "d" }), { description = "Move window down in column" })

-- Scrolling layout: move the whole column, no combining (Super+Ctrl+arrow)
hl.bind("CTRL + SUPER + Left", hl.dsp.layout("swapcol l"), { description = "Move column left" })
hl.bind("CTRL + SUPER + Right", hl.dsp.layout("swapcol r"), { description = "Move column right" })

------------------------------------------------------------
-- Apps / scripts
------------------------------------------------------------
hl.bind("SUPER + Y", hl.dsp.exec_cmd("/home/menk/.config/toggle-hdr.sh"), { description = "Toggle HDR" })
hl.bind(
	"SUPER + ALT + R",
	hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/layout-switch.sh"),
	{ description = "Switch layouts" }
)
hl.bind(
	"CTRL + SUPER + Slash",
	hl.dsp.exec_cmd("kitty nvim ~/.config/illogical-impulse/config.json"),
	{ description = "Edit shell config" }
)
hl.bind(
	"CTRL + SUPER + ALT + Plus",
	hl.dsp.exec_cmd("kitty nvim ~/.config/hypr/custom/keybinds.lua"),
	{ description = "Edit extra keybinds" }
)
hl.bind(
	"SUPER + B",
	hl.dsp.exec_cmd(
		[[~/.config/hypr/hyprland/scripts/launch_first_available.sh "google-chrome-stable" "zen-browser" "firefox" "brave" "chromium" "microsoft-edge-stable" "opera" "librewolf"]]
	),
	{ description = "Browser" }
)
hl.bind(
	"SUPER + C",
	hl.dsp.exec_cmd(
		[[~/.config/hypr/hyprland/scripts/launch_first_available.sh "command -v nvim && kitty -1 nvim" "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v micro && kitty -1 micro"]]
	),
	{ description = "Code editor" }
)

------------------------------------------------------------
-- Workspace: focus down / up (Super+U / Super+I)
------------------------------------------------------------
hl.bind("SUPER + U", hl.dsp.focus({ workspace = "r+1" }), { description = "Focus workspace down" })
hl.bind("SUPER + I", hl.dsp.focus({ workspace = "r-1" }), { description = "Focus workspace up" })

------------------------------------------------------------
-- Workspace: move window to workspace
--   Super+Shift+N        -> move and follow
--   Super+Ctrl+Shift+N   -> move silently
------------------------------------------------------------
for i = 1, 10 do
	hl.bind("SUPER + SHIFT + " .. (i % 10), function()
		hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
	end, { description = "Move window to workspace " .. i })
	hl.bind("CTRL + SUPER + SHIFT + " .. (i % 10), function()
		hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
	end, { description = "Move window to workspace " .. i .. " (silent)" })
end

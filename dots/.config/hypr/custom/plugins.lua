if hl.plugin.hyprglass then
	local hg = hl.plugin.hyprglass

	-- ── Material You glass tint ───────────────────────────────────────────
	-- The shell's liquid glass is not tinted with a fixed colour: it blends the
	-- wallpaper's dominant colour into the Material surface and paints the
	-- panel with that at `appearance.liquid.realGlass.opacity`. hyprglass
	-- composites its tint the same way (`mix(scene, tintColor, tintAlpha)`), so
	-- reproducing the recipe here makes window glass read as the same material
	-- as the bar and sidebars instead of a hardcoded blue-grey.
	--
	--   seed  = 0.8 * wallpaper_seed + 0.2 * primary_container
	--   tint  = w * background + (1 - w) * seed   (w = 0.6 for a dark seed in
	--                                              dark mode, else 0.5)
	--   alpha = GLASS_OPACITY
	--
	-- Mirrors modules/bar/BarContent.qml (blendedColors) and
	-- modules/common/widgets/GlassBackground.qml (realGlassColor) in the shell.
	-- Tokens come from ~/.config/hypr/hyprland/hyprglass-colors.lua, rendered
	-- by the wallpaper-colour pipeline; the fallback below is the old static
	-- tint, used until that file exists.
	local GLASS_OPACITY = 0.7 -- keep in step with appearance.liquid.realGlass.opacity
	local FALLBACK_TINT = 0x8899aa22

	local tint = { dark = FALLBACK_TINT, light = FALLBACK_TINT }

	do
		-- ColorUtils.mix(a, b, p) weights the *first* colour by p.
		local function mix(a, b, p)
			return {
				p * a[1] + (1 - p) * b[1],
				p * a[2] + (1 - p) * b[2],
				p * a[3] + (1 - p) * b[3],
			}
		end

		local function hex2rgb(hex)
			if type(hex) ~= "string" then
				return nil
			end
			hex = hex:gsub("^#", "")
			if not hex:match("^%x%x%x%x%x%x$") then
				return nil -- unrendered template placeholder, or garbage
			end
			return {
				tonumber(hex:sub(1, 2), 16) / 255,
				tonumber(hex:sub(3, 4), 16) / 255,
				tonumber(hex:sub(5, 6), 16) / 255,
			}
		end

		-- hyprglass wants RRGGBBAA, where the alpha is the tint strength.
		local function rgba(c, alpha)
			local function ch(v)
				return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
			end
			return ch(c[1]) * 0x1000000 + ch(c[2]) * 0x10000 + ch(c[3]) * 0x100 + ch(alpha)
		end

		-- Qt's hslLightness, which is what AdaptedMaterialScheme branches on.
		local function is_dark(c)
			return (math.max(c[1], c[2], c[3]) + math.min(c[1], c[2], c[3])) / 2 < 0.5
		end

		local function glass_tint(palette, darkmode)
			local source = hex2rgb(palette and palette.source)
			local container = hex2rgb(palette and palette.primary_container)
			local background = hex2rgb(palette and palette.background)
			if not (source and container and background) then
				return nil
			end
			local seed = mix(source, container, 0.8)
			local weight = (darkmode and is_dark(seed)) and 0.6 or 0.5
			return rgba(mix(background, seed, weight), GLASS_OPACITY)
		end

		-- A broken or half-written generated file must never take the whole
		-- Hyprland config down with it.
		local path = HOME .. "/.config/hypr/hyprland/hyprglass-colors.lua"
		if is_file_exists(path) then
			local ok, colors = pcall(dofile, path)
			if ok and type(colors) == "table" then
				tint.dark = glass_tint(colors.dark, true) or tint.dark
				tint.light = glass_tint(colors.light, false) or tint.light
			end
		end
	end

	hg.config({
		default_theme = "dark",
		default_preset = "apple",
		tint_color = tint.dark,
		enabled = true,
		manage_window_blur = true,

		brightness = 0.9,
		dark = { brightness = 0.82, tint_color = tint.dark },
		light = { adaptive_boost = 0.5, tint_color = tint.light },

		layers = { enabled = 1 },
	})

	-- Layer surfaces: each call whitelists the namespace and configures it
	hg.layer("waybar", { preset = "subtle", mask_threshold = 0.05 })
	hg.layer("kitty", { preset = "clear" })
	hg.layer("swaync")
	hg.layer("quickshell:bezel", { preset = "ui", mask_threshold = 0.3 })
	hg.layer("debug-panel", { exclude = true })

	-- Presets
	hg.preset("clear", {
		glass_opacity = 0.8,
		blur_strength = 1.5,
		dark = { brightness = 0.7 },
		light = { brightness = 1.2 },
	})

	hg.preset("contrasted", {
		inherits = "high_contrast",
		contrast = 1.2,
		adaptive_dim = 1.5,
		dark = { tint_color = 0x02142aa9 },
	})

	hg.preset("apple", {
		-- Tuned down from the pasted-in defaults: edge_thickness was 0.3, double
		-- the documented 0.0-0.15 range, which likely pushed the heavy-distortion
		-- refraction zone across most of the window instead of just a thin bezel.
		-- That, plus a strong blur/refraction, was the "clarity lost" — less of
		-- both here, so more of what's behind reads as recognizable wallpaper
		-- rather than mush. glass_opacity/adaptive_dim pulled down too, so less
		-- gets crushed/dimmed and more of the background is visible through it.
		blur_strength = 1.8,
		blur_iterations = 3,
		refraction_strength = 0.65,
		chromatic_aberration = 0.45,
		fresnel_strength = 0.8,
		specular_strength = 0.95,
		edge_thickness = 0.6,
		lens_distortion = 0.3,
		-- Wallpaper-derived tints, see the recipe at the top of this file.
		dark = {
			brightness = 0.95,
			contrast = 1.3,
			saturation = 0.85,
			vibrancy = 0.9,
			adaptive_dim = 0.8,
			tint_color = tint.dark,
		},
		light = {
			brightness = 1.05,
			contrast = 1.1,
			saturation = 0.85,
			vibrancy = 0.12,
			adaptive_dim = 0.2,
			tint_color = tint.light,
		},
	})
end

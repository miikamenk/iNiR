local M = {}

function M.setup()
	require("base16-colorscheme").setup({
		-- Background tones
		base00 = "{{colors.surface.default.hex}}", -- Default Background
		base01 = "{{colors.surface_container.default.hex}}", -- Lighter Background (status bars)
		base02 = "{{colors.secondary_container.default.hex}}", -- Selection Background
		base03 = "{{colors.outline.default.hex}}", -- Comments, Invisibles

		-- Foreground tones (now properly graduated)
		base04 = "{{colors.on_surface_variant.default.hex}}", -- Dark Foreground (status bars)
		base05 = "{{colors.on_surface.default.hex}}", -- Default Foreground
		base06 = "{{colors.inverse_on_surface.default.hex}}", -- Light Foreground
		base07 = "{{colors.on_background.default.hex}}", -- Lightest Foreground

		-- Accent colors (using full-strength tokens instead of dim/container variants)
		base08 = "{{colors.error.default.hex}}", -- Variables, XML Tags, Errors
		base09 = "{{colors.tertiary.default.hex}}", -- Integers, Constants
		base0A = "{{colors.secondary.default.hex}}", -- Classes, Search Background
		base0B = "{{colors.primary.default.hex}}", -- Strings, Diff Inserted
		base0C = "{{colors.tertiary_fixed.default.hex}}", -- Regex, Escape Chars  (was _dim)
		base0D = "{{colors.primary_fixed.default.hex}}", -- Functions, Methods   (was _dim)
		base0E = "{{colors.secondary_fixed.default.hex}}", -- Keywords, Storage    (was _dim)
		base0F = "{{colors.on_error_container.default.hex}}", -- Deprecated, Embedded (was error_container bg)
	})
end

-- Register a signal handler for SIGUSR1 (matugen updates)
local signal = vim.uv.new_signal()
signal:start(
	"sigusr1",
	vim.schedule_wrap(function()
		package.loaded["matugen"] = nil
		require("matugen").setup()
	end)
)

return M

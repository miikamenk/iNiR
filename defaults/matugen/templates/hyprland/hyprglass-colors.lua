-- iNiR Material You colours for the hyprglass plugin
-- Rendered by iNiR's unified wallpaper-colour pipeline — do not edit by hand.
--
-- Raw palette tokens only. The blend that turns these into a glass tint lives
-- in ~/.config/hypr/custom/plugins.lua, because the template language has no
-- arithmetic and the recipe has to stay readable next to the preset it feeds.
--
-- `source` is the seed colour extracted from the wallpaper — the template-side
-- counterpart of the shell's ColorQuantizer dominant colour.

return {
	dark = {
		source = "{{colors.source_color.dark.hex_stripped}}",
		background = "{{colors.background.dark.hex_stripped}}",
		primary_container = "{{colors.primary_container.dark.hex_stripped}}",
	},
	light = {
		source = "{{colors.source_color.light.hex_stripped}}",
		background = "{{colors.background.light.hex_stripped}}",
		primary_container = "{{colors.primary_container.light.hex_stripped}}",
	},
}

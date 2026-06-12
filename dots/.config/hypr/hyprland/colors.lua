hl.config({
    general = {
        col = {
            -- Focus ring: accent on the focused window, transparent otherwise
            active_border   = "rgba(EABAC8ff)",
            inactive_border = "rgba(1B1B1B00)",
        },
    },
    misc = {
        background_color = "rgba(131313FF)",
    },
})

hl.window_rule({
    match        = { pin = 1 },
    border_color = "rgba(EABAC8AA) rgba(EABAC877)",
})

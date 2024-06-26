---@diagnostic disable

data:extend({
    {
        type = "shortcut",
        name = "fp_open_interface",
        action = "lua",
        toggleable = false,
        order = "fp-a[open]",
        associated_control_input = "fp_toggle_interface",
        icon = "__factoryplanner__/graphics/shortcut_open_x32.png",
        icon_size = 32,
        small_icon = "__factoryplanner__/graphics/shortcut_open_x24.png",
        small_icon_size = 24
    }
})

---@diagnostic disable

data:extend({
    {
        type = "shortcut",
        name = "fp_open_interface",
        action = "lua",
        toggleable = false,
        order = "fp-a[open]",
        associated_control_input = "fp_toggle_interface",
        icon =
        {
            filename = "__factoryplanner__/graphics/shortcut_open_x32.png",
            priority = "extra-high-no-scale",
            size = 32,
            scale = 1,
            flags = {"icon"}
        },
        small_icon =
        {
            filename = "__factoryplanner__/graphics/shortcut_open_black_x24.png",
            priority = "extra-high-no-scale",
            size = 24,
            scale = 1,
            flags = {"icon"}
        },
        disabled_small_icon =
        {
            filename = "__factoryplanner__/graphics/shortcut_open_white_x24.png",
            priority = "extra-high-no-scale",
            size = 24,
            scale = 1,
            flags = {"icon"}
        }
    }
})

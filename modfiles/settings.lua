data:extend({
    {
        type = "bool-setting",
        name = "fp_display_gui_button",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "a"
    },
    {
        type = "bool-setting",
        name = "fp_pause_on_interface",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "b"
    },
    {
        type = "int-setting",
        name = "fp_subfactory_items_per_row",
        setting_type = "runtime-per-user",
        default_value = 8,
        allowed_values = {6, 7, 8, 9, 10, 11, 12},
        order = "c"
    },
    {
        type = "int-setting",
        name = "fp_floor_recipes_at_once",
        setting_type = "runtime-per-user",
        default_value = 14,
        allowed_values = {8, 10, 12, 14, 16, 18, 20},
        order = "d"
    },
    {
        type = "string-setting",
        name = "fp_default_timescale",
        setting_type = "runtime-per-user",
        default_value = "one_minute",
        allowed_values = {"one_second", "one_minute", "one_hour"},
        order = "e"
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "belts",
        allowed_values = {"belts", "lanes"},
        order = "f"
    },
    {
        type = "double-setting",
        name = "fp_indicate_rounding",
        setting_type = "runtime-per-user",
        default_value = 0,
        minimum_value = 0,
        maximum_value = 0.4,
        order = "g"
    }
})
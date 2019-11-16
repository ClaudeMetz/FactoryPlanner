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
        type = "bool-setting",
        name = "fp_performance_mode",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "c"
    },
    {
        type = "int-setting",
        name = "fp_subfactory_items_per_row",
        setting_type = "runtime-per-user",
        default_value = 8,
        allowed_values = {6, 7, 8, 9, 10, 11, 12},
        order = "d"
    },
    {
        type = "int-setting",
        name = "fp_floor_recipes_at_once",
        setting_type = "runtime-per-user",
        default_value = 14,
        allowed_values = {8, 10, 12, 14, 16, 18, 20},
        order = "e"
    },
    {
        type = "string-setting",
        name = "fp_default_timescale",
        setting_type = "runtime-per-user",
        default_value = "one_minute",
        allowed_values = {"one_second", "one_minute", "one_hour"},
        order = "f"
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "belts",
        allowed_values = {"belts", "lanes"},
        order = "g"
    },
    {
        type = "bool-setting",
        name = "fp_line_comments",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "h"
    },
    {
        type = "bool-setting",
        name = "fp_ingredient_satisfaction",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "i"
    },
    {
        type = "bool-setting",
        name = "fp_round_button_numbers",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "j"
    },
    {
        type = "double-setting",
        name = "fp_indicate_rounding",
        setting_type = "runtime-per-user",
        default_value = 0,
        minimum_value = 0,
        maximum_value = 0.4,
        order = "k"
    }
})
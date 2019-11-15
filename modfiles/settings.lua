data:extend({
    {
        type = "bool-setting",
        name = "fp_display_gui_button",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "a",
        localised_name = {"mod-setting-name.fp_display_gui_button"},
        localised_description = {"mod-setting-description.fp_display_gui_button"}
    },
    {
        type = "bool-setting",
        name = "fp_pause_on_interface",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "b",
        localised_name = {"mod-setting-name.fp_pause_on_interface"},
        localised_description = {"mod-setting-description.fp_pause_on_interface"}
    },
    {
        type = "bool-setting",
        name = "fp_performance_mode",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "c",
        localised_name = {"mod-setting-name.fp_performance_mode"},
        localised_description = {"mod-setting-description.fp_performance_mode"}
    },
    {
        type = "int-setting",
        name = "fp_subfactory_items_per_row",
        setting_type = "runtime-per-user",
        default_value = 8,
        allowed_values = {6, 7, 8, 9, 10, 11, 12},
        order = "d",
        localised_name = {"mod-setting-name.fp_subfactory_items_per_row"},
        localised_description = {"mod-setting-description.fp_subfactory_items_per_row"}
    },
    {
        type = "int-setting",
        name = "fp_floor_recipes_at_once",
        setting_type = "runtime-per-user",
        default_value = 14,
        allowed_values = {8, 10, 12, 14, 16, 18, 20},
        order = "e",
        localised_name = {"mod-setting-name.fp_floor_recipes_at_once"},
        localised_description = {"mod-setting-description.fp_floor_recipes_at_once"}
    },
    {
        type = "string-setting",
        name = "fp_default_timescale",
        setting_type = "runtime-per-user",
        default_value = "one_minute",
        allowed_values = {"one_second", "one_minute", "one_hour"},
        order = "f",
        localised_name = {"mod-setting-name.fp_default_timescale"},
        localised_description = {"mod-setting-description.fp_default_timescale"}
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "belts",
        allowed_values = {"belts", "lanes"},
        order = "g",
        localised_name = {"mod-setting-name.fp_view_belts_or_lanes"},
        localised_description = {"mod-setting-description.fp_view_belts_or_lanes"}
    },
    {
        type = "bool-setting",
        name = "fp_line_comments",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "h",
        localised_name = {"mod-setting-name.fp_line_comments"},
        localised_description = {"mod-setting-description.fp_line_comments"}
    },
    {
        type = "bool-setting",
        name = "fp_ingredient_satisfaction",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "i",
        localised_name = {"mod-setting-name.fp_ingredient_satisfaction"},
        localised_description = {"mod-setting-description.fp_ingredient_satisfaction"}
    },
    {
        type = "bool-setting",
        name = "fp_round_button_numbers",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "j",
        localised_name = {"mod-setting-name.fp_round_button_numbers"},
        localised_description = {"mod-setting-description.fp_round_button_numbers"}
    },
    {
        type = "double-setting",
        name = "fp_indicate_rounding",
        setting_type = "runtime-per-user",
        default_value = 0,
        minimum_value = 0,
        maximum_value = 0.4,
        order = "k",
        localised_name = {"mod-setting-name.fp_indicate_rounding"},
        localised_description = {"mod-setting-description.fp_indicate_rounding"}
    }
})
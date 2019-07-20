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
        name = "fp_show_hints",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "b",
        localised_name = {"mod-setting-name.fp_show_hints"},
        localised_description = {"mod-setting-description.fp_show_hints"}
    },
    {
        type = "bool-setting",
        name = "fp_pause_on_interface",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "c",
        localised_name = {"mod-setting-name.fp_pause_on_interface"},
        localised_description = {"mod-setting-description.fp_pause_on_interface"}
    },
    {
        type = "int-setting",
        name = "fp_subfactory_items_per_row",
        setting_type = "runtime-per-user",
        default_value = 8,
        allowed_values = {5, 6, 7, 8, 9, 10, 11},
        order = "d",
        localised_name = {"mod-setting-name.fp_subfactory_items_per_row"},
        localised_description = {"mod-setting-description.fp_subfactory_items_per_row"}
    },
    {
        type = "int-setting",
        name = "fp_floor_recipes_at_once",
        setting_type = "runtime-per-user",
        default_value = 14,
        allowed_values = {8, 10, 12, 14, 16, 18, 20, 22},
        order = "e",
        localised_name = {"mod-setting-name.fp_floor_recipes_at_once"},
        localised_description = {"mod-setting-description.fp_floor_recipes_at_once"}
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "Belts",
        allowed_values = {"Belts", "Lanes"},
        order = "f",
        localised_name = {"mod-setting-name.fp_view_belts_or_lanes"},
        localised_description = {"mod-setting-description.fp_view_belts_or_lanes"}
    },
    {
        type = "double-setting",
        name = "fp_indicate_rounding",
        setting_type = "runtime-per-user",
        default_value = 0,
        minimum_value = 0,
        maximum_value = 0.4,
        order = "g",
        localised_name = {"mod-setting-name.fp_indicate_rounding"},
        localised_description = {"mod-setting-description.fp_indicate_rounding"}
    }
})
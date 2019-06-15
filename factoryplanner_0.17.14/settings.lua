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
        type = "int-setting",
        name = "fp_subfactory_items_per_row",
        setting_type = "runtime-per-user",
        default_value = 8,
        allowed_values = {5, 6, 7, 8, 9, 10, 11},
        order = "b",
        localised_name = {"mod-setting-name.fp_subfactory_items_per_row"},
        localised_description = {"mod-setting-description.fp_subfactory_items_per_row"}
    },
    {
        type = "int-setting",
        name = "fp_floor_recipes_at_once",
        setting_type = "runtime-per-user",
        default_value = 14,
        allowed_values = {8, 10, 12, 14, 16, 18, 20, 22},
        order = "c",
        localised_name = {"mod-setting-name.fp_floor_recipes_at_once"},
        localised_description = {"mod-setting-description.fp_floor_recipes_at_once"}
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "Belts",
        allowed_values = {"Belts", "Lanes"},
        order = "d",
        localised_name = {"mod-setting-name.fp_view_belts_or_lanes"},
        localised_description = {"mod-setting-description.fp_view_belts_or_lanes"}
    },
    {
        type = "bool-setting",
        name = "fp_show_hints",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "e",
        localised_name = {"mod-setting-name.fp_show_hints"},
        localised_description = {"mod-setting-description.fp_show_hints"}
    }
})
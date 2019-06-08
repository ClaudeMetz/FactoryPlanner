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
        default_value = 7,
        allowed_values = {5, 6, 7, 8, 9},
        order = "b",
        localised_name = {"mod-setting-name.fp_subfactory_items_per_row"},
        localised_description = {"mod-setting-description.fp_subfactory_items_per_row"}
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "Belts",
        allowed_values = {"Belts", "Lanes"},
        order = "c",
        localised_name = {"mod-setting-name.fp_view_belts_or_lanes"},
        localised_description = {"mod-setting-description.fp_view_belts_or_lanes"}
    },
    {
        type = "bool-setting",
        name = "fp_show_hints",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "d",
        localised_name = {"mod-setting-name.fp_show_hints"},
        localised_description = {"mod-setting-description.fp_show_hints"}
    }
})
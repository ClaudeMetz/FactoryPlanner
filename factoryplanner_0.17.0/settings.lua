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
        default_value = 6,
        allowed_values = {4, 5, 6, 7, 8},
        order = "b",
        localised_name = {"mod-setting-name.fp_subfactory_items_per_row"},
        localised_description = {"mod-setting-description.fp_subfactory_items_per_row"}
    },
    {
        type = "bool-setting",
        name = "fp_show_disabled_recipe",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "c",
        localised_name = {"mod-setting-name.fp_show_disabled_recipe"},
        localised_description = {"mod-setting-description.fp_show_disabled_recipe"}
    }
})
data:extend({
    {
        type = "bool-setting",
        name = "fp_display_gui_button",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "a"
    },
    {
        type = "int-setting",
        name = "fp_products_per_row",
        setting_type = "runtime-per-user",
        default_value = 7,
        allowed_values = {5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
        order = "b"
    },
    {
        type = "int-setting",
        name = "fp_subfactory_list_rows",
        setting_type = "runtime-per-user",
        default_value = 24,
        allowed_values = {14, 16, 18, 20, 22, 24, 26, 28, 30, 32},
        order = "c"
    },
    {
        type = "string-setting",
        name = "fp_default_timescale",
        setting_type = "runtime-per-user",
        default_value = "one_minute",
        allowed_values = {"one_second", "one_minute", "one_hour"},
        order = "d"
    },
    {
        type = "string-setting",
        name = "fp_view_belts_or_lanes",
        setting_type = "runtime-per-user",
        default_value = "belts",
        allowed_values = {"belts", "lanes"},
        order = "e"
    },
    {
        type = "bool-setting",
        name = "fp_prefer_product_picker",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "f"
    },
    {
        type = "bool-setting",
        name = "fp_prefer_matrix_solver",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "g"
    },
})

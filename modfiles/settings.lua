-- Determine the active mods compatible with the alt-action setting
local alt_action_values = {"none"}
local compatible_mods = {
    [1] = {internal_name = "fnei", name = "FNEI"},
    [2] = {internal_name = "wiiruf", name = "what-is-it-really-used-for"},
    [3] = {internal_name = "recipebook", name = "RecipeBook"}
}

for _, mod in ipairs(compatible_mods) do
    if mods[mod.name] then table.insert(alt_action_values, mod.internal_name) end
end

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
        default_value = 8,
        allowed_values = {5, 6, 7, 8, 9, 10, 11, 12},
        order = "b"
    },
    {
        type = "int-setting",
        name = "fp_subfactory_list_rows",
        setting_type = "runtime-per-user",
        default_value = 20,
        allowed_values = {12, 14, 16, 18, 20, 22, 24, 26},
        order = "c"
    },
    {
        type = "string-setting",
        name = "fp_alt_action",
        setting_type = "runtime-per-user",
        default_value = "none",
        allowed_values = alt_action_values,
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
    }
})
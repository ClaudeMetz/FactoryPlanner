---@diagnostic disable

data:extend({
    {
        type = "selection-tool",
        name = "fp_beacon_selector",
        icon = "__factoryplanner__/graphics/beacon_selector.png",
        icon_size = 32,
        flags = {"only-in-cursor"},
        subgroup = "other",
        order = "z_fp1",
        hidden = true,
        stack_size = 1,
        select = {
            mode = "entity-with-health",
            border_color = { r = 0.75, g = 0, b = 0.75 },
            cursor_box_type = "entity",
            entity_filter_mode = "whitelist",
            entity_type_filters = {"beacon"}
        },
        alt_select = {
            mode = "nothing",
            border_color = { r = 0.75, g = 0, b = 0.75 },
            cursor_box_type = "entity"
        }
    }
})

data:extend({
    {
        type = "selection-tool",
        name = "fp_beacon_selector",
        icon = "__factoryplanner__/graphics/beacon_selector.png",
        icon_size = 32,
        flags = {"hidden", "only-in-cursor"},
        subgroup = "other",
        order = "z_fp",
        stack_size = 1,
        stackable = false,
        show_in_library = false,
        selection_color = { r = 0.75, g = 0, b = 0.75 },
        alt_selection_color = { r = 0.75, g = 0, b = 0.75 },
        selection_mode = {"entity-with-health"},
        alt_selection_mode = {"nothing"},
        selection_cursor_box_type = "entity",
        alt_selection_cursor_box_type = "entity",
        entity_filter_mode = "whitelist",
        entity_type_filters = {"beacon"}
    }
})
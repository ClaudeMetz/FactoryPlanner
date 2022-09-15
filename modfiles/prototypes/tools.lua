local beacon_selector = {
    type = "selection-tool",
    name = "fp_beacon_selector",
    icon = "__factoryplanner__/graphics/beacon_selector.png",
    icon_size = 32,
    flags = {"hidden", "only-in-cursor"},
    subgroup = "other",
    order = "z_fp1",
    stack_size = 1,
    selection_color = { r = 0.75, g = 0, b = 0.75 },
    alt_selection_color = { r = 0.75, g = 0, b = 0.75 },
    selection_mode = {"entity-with-health"},
    alt_selection_mode = {"nothing"},
    selection_cursor_box_type = "entity",
    alt_selection_cursor_box_type = "entity",
    entity_filter_mode = "whitelist",
    entity_type_filters = {"beacon"}
}

local cursor_blueprint = util.table.deepcopy(data.raw["blueprint"]["blueprint"])
cursor_blueprint.name = "fp_cursor_blueprint"
cursor_blueprint.order = "z_fp2"
table.insert(cursor_blueprint.flags, "hidden")
table.insert(cursor_blueprint.flags, "only-in-cursor")

data:extend{beacon_selector, cursor_blueprint}

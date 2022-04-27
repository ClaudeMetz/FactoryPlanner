-- The main GUI parts for the compact dialog
compact_subfactory = {}

-- ** LOCAL UTIL **
-- Checks whether the given (internal) prototype can be blueprinted
local function put_into_cursor(player, tags, _)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- We don't need to care about relevant lines here because this only gets called on lines without subfloor
    local object = line[tags.type]

    if game.entity_prototypes[object.proto.name].has_flag("not-blueprintable") then return end

    local module_list = {}
    for _, module in pairs(ModuleSet.get_in_order(object.module_set)) do
        module_list[module.proto.name] = module.amount
    end

    local blueprint_entity = {
        entity_number = 1,
        name = object.proto.name,
        position = {0, 0},
        items = module_list,
        recipe = (tags.type == "machine") and line.recipe.proto.name or nil
    }

    ui_util.create_cursor_blueprint(player, {blueprint_entity})
end


local function add_recipe_button(parent_flow, line, relevant_line)
    local recipe_proto = relevant_line.recipe.proto
    local style = (line.subfloor ~= nil) and "flib_slot_button_blue_small" or "flib_slot_button_default_small"
    local tooltip = {"", {"fp.tt_title", recipe_proto.localised_name}}
    if line.subfloor ~= nil then table.insert(tooltip, {"", "\n", {"fp.compact_recipe_subfloor_tt"}}) end
    parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="open_compact_subfloor", line_id=line.id},
      sprite=recipe_proto.sprite, tooltip=tooltip, enabled=(line.subfloor ~= nil), style=style,
      mouse_button_filter={"left"}}
end

local function add_checkmark_button(parent_flow, line, relevant_line)
    local sprite = (relevant_line.done) and "utility/check_mark" or "fp_sprite_check_mark_green"
    local style = (relevant_line.done) and "fp_button_slot_green" or "flib_slot_default"
    local checkmark_button = parent_flow.add{type="sprite-button", sprite=sprite, style=style,
      tags={mod="fp", on_gui_click="checkmark_compact_line", line_id=line.id}, mouse_button_filter={"left"}}
    checkmark_button.style.size = 20
    checkmark_button.style.padding = -1
end

local function add_modules_flow(parent_flow, module_set)
    for _, module in ipairs(ModuleSet.get_in_order(module_set)) do
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", {"fp.tt_title", module.proto.localised_name}, number_line}

        parent_flow.add{type="sprite-button", sprite=module.proto.sprite, tooltip=tooltip,
          number=module.amount, style="flib_slot_button_default_small", enabled=false}
    end
end

local function add_machine_flow(parent_flow, line)
    if line.subfloor == nil then
        local machine_flow = parent_flow.add{type="flow", direction="horizontal"}
        local machine_proto = line.machine.proto

        local machine_count = math.ceil(line.machine.count)
        local tooltip_count = ui_util.format_number(line.machine.count, 4)
        if machine_count == "0" and line.production_ratio > 0 then
            tooltip_count = "<0.0001"
            machine_count = "0.01"  -- shows up as 0.0 on the button
        end

        local plural_parameter = (machine_count == "1") and 1 or 2
        local number_line = {"", "\n", tooltip_count, " ", {"fp.pl_machine", plural_parameter}, "\n"}
        local action_line = {"fp.tut_action_line", {"fp.tut_left"}, {"fp.tut_put_into_cursor"}}
        local tooltip = {"", {"fp.tt_title", machine_proto.localised_name}, number_line, action_line}

        machine_flow.add{type="sprite-button", sprite=machine_proto.sprite, number=machine_count, tooltip=tooltip,
          tags={mod="fp", on_gui_click="put_into_cursor", type="machine", line_id=line.id},
          style="flib_slot_button_default_small", mouse_button_filter={"left"}}

        add_modules_flow(machine_flow, line.machine.module_set)
    end
end

local function add_beacon_flow(parent_flow, line)
    if line.subfloor == nil and line.beacon ~= nil then
        local beacon_flow = parent_flow.add{type="flow", direction="horizontal"}
        local beacon_proto = line.beacon.proto

        local plural_parameter = (line.beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"", "\n", line.beacon.amount, " ", {"fp.pl_beacon", plural_parameter}, "\n"}
        local action_line = {"fp.tut_action_line", {"fp.tut_left"}, {"fp.tut_put_into_cursor"}}
        local tooltip = {"", {"fp.tt_title", beacon_proto.localised_name}, number_line, action_line}

        beacon_flow.add{type="sprite-button", sprite=beacon_proto.sprite, number=line.beacon.amount,
          tooltip=tooltip, tags={mod="fp", on_gui_click="put_into_cursor", type="beacon", line_id=line.id},
          style="flib_slot_button_default_small", mouse_button_filter={"left"}}

        add_modules_flow(beacon_flow, line.beacon.module_set)
    end
end


local function add_item_flow(item_class, item_count, button_color, metadata)
    local column_count = math.max(math.ceil(item_count / 2), 1)
    local item_table = metadata.parent.add{type="table", column_count=column_count}

    for _, item in ipairs(Line.get_in_order(metadata.line, item_class)) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not metadata.line.subfloor) and metadata.line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata, item, nil, machine_count)
        if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", {"fp.tt_title", item.proto.localised_name}, number_line}

        item_table.add{type="sprite-button", sprite=item.proto.sprite, number=amount, tooltip=tooltip,
          style="flib_slot_button_" .. button_color .. "_small", enabled=false}

        ::skip_item::
    end
end


-- ** TOP LEVEL **
function compact_subfactory.build(player)
    local ui_state = data_util.get("ui_state", player)
    local compact_elements = ui_state.compact_elements

    -- Content frame
    local content_frame = compact_elements.compact_frame.add{type="frame", direction="vertical",
      style="inside_deep_frame"}
    content_frame.style.vertically_stretchable = true

    local subheader = content_frame.add{type="frame", direction="vertical", style="subheader_frame"}
    subheader.style.maximal_height = 100  -- large value to nullify maximal_height

    -- Flow view state
    local flow_view_state = subheader.add{type="flow", direction="horizontal"}
    flow_view_state.style.padding = {4, 4, 0, 0}
    flow_view_state.add{type="empty-widget", style="flib_horizontal_pusher"}

    local table_view_state = view_state.build(player, flow_view_state)
    compact_elements["view_state_table"] = table_view_state

    subheader.add{type="line", direction="horizontal"}

    -- Flow navigation
    local flow_navigation = subheader.add{type="flow", direction="horizontal"}
    flow_navigation.style.vertical_align = "center"
    flow_navigation.style.margin = {4, 8}

    local label_name = flow_navigation.add{type="label"}
    label_name.style.font = "heading-2"
    label_name.style.maximal_width = 260
    compact_elements["name_label"] = label_name

    local label_level = flow_navigation.add{type="label"}
    label_level.style.margin = {0, 6, 0, 6}
    compact_elements["level_label"] = label_level

    local button_floor_up = flow_navigation.add{type="sprite-button", sprite="fp_sprite_arrow_line_up",
      tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_compact_floor", destination="up"},
      style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    compact_elements["floor_up_button"] = button_floor_up

    local button_floor_top = flow_navigation.add{type="sprite-button", sprite="fp_sprite_arrow_line_bar_up",
      tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_compact_floor", destination="top"},
      style="fp_sprite-button_rounded_mini", mouse_button_filter={"left"}}
    compact_elements["floor_top_button"] = button_floor_top

    -- Production table
    local scroll_pane_production = content_frame.add{type="scroll-pane", direction="vertical",
      style="flib_naked_scroll_pane_no_padding"}
    scroll_pane_production.style.horizontally_stretchable = true

    local table_production = scroll_pane_production.add{type="table", column_count=6, style="fp_table_production"}
    table_production.vertical_centering = false
    table_production.style.horizontal_spacing = 12
    table_production.style.vertical_spacing = 8
    table_production.style.padding = {4, 8}
    compact_elements["production_table"] = table_production

    compact_subfactory.refresh(player)
end

function compact_subfactory.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local compact_elements = ui_state.compact_elements
    local subfactory = ui_state.context.subfactory
    local current_level = subfactory.selected_floor.level

    view_state.refresh(player, compact_elements.view_state_table)

    compact_elements.name_label.caption = Subfactory.tostring(subfactory, false)

    compact_elements.level_label.caption = {"fp.bold_label", {"", "-   ", {"fp.level"}, " ", current_level}}
    compact_elements.floor_up_button.enabled = (current_level > 1)
    compact_elements.floor_top_button.enabled = (current_level > 1)

    local production_table = compact_elements.production_table
    production_table.clear()

    local production_columns = {{"fp.pu_recipe", 1}, {"fp.pu_machine", 2}, {"fp.pu_product", 2},
      {"fp.pu_byproduct", 2}, {"fp.pu_ingredient", 2}, ""}
    for _, caption in ipairs(production_columns) do
        local label_header = production_table.add{type="label", caption=caption, style="bold_label"}
        label_header.style.bottom_margin = 6
    end

    local lines = Floor.get_in_order(ui_state.context.floor, "Line")
    local view_state_metadata = view_state.generate_metadata(player, subfactory, 4, true)

    local max_ingredient_count = 0
    for _, line in ipairs(lines) do  -- count ingredients to determine its table size
        max_ingredient_count = math.max(max_ingredient_count, line.Ingredient.count)
    end

    for _, line in ipairs(lines) do -- build the individual lines
        local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

        -- Recipe and Checkmark
        local recipe_flow = production_table.add{type="flow", direction="horizontal"}
        recipe_flow.style.vertical_align = "center"
        add_checkmark_button(recipe_flow, line, relevant_line)
        add_recipe_button(recipe_flow, line, relevant_line)

        -- Machine and Beacon
        local machines_flow = production_table.add{type="flow", direction="vertical"}
        add_machine_flow(machines_flow, line)
        add_beacon_flow(machines_flow, line)

        -- Products, Byproducts and Ingredients
        local metadata = {parent=production_table, line=line, view_state_metadata=view_state_metadata}
        add_item_flow("Product", line.Product.count, "default", metadata)
        add_item_flow("Byproduct", line.Byproduct.count, "red", metadata)
        add_item_flow("Ingredient", max_ingredient_count, "green", metadata)

        production_table.add{type="empty-widget", style="flib_horizontal_pusher"}
    end
end


-- ** EVENTS **
compact_subfactory.gui_events = {
    on_gui_click = {
        {
            name = "change_compact_floor",
            handler = (function(player, tags, _)
                local floor_changed = ui_util.context.change_floor(player, tags.destination)
                if floor_changed then compact_subfactory.refresh(player) end
            end)
        },
        {
            name = "open_compact_subfloor",
            handler = (function(player, tags, _)
                -- Can only be called on lines with subfloors, so no need to check
                local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
                ui_util.context.set_floor(player, line.subfloor)
                compact_subfactory.refresh(player)
            end)
        },
        {
            name = "checkmark_compact_line",
            handler = (function(player, tags, _)
                local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
                local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
                relevant_line.done = not relevant_line.done
                compact_subfactory.refresh(player)
            end)
        },
        {
            name = "put_into_cursor",
            handler = put_into_cursor
        }
    }
}

-- The main GUI parts for the compact dialog
compact_subfactory = {}

-- ** LOCAL UTIL **
local function determine_available_columns(lines, frame_width)
    local frame_border_size = 12
    local table_padding, table_spacing = 8, 12
    local recipe_and_check_width = 58
    local button_width, button_spacing = 36, 4

    local max_module_count = 0
    for _, line in pairs(lines) do
        if line.subfloor == nil then
            local module_kinds = ModuleSet.get_module_kind_amount(line.machine.module_set)
            max_module_count = math.max(max_module_count, module_kinds)
        end
        if line.beacon ~= nil then
            local module_kinds = ModuleSet.get_module_kind_amount(line.beacon.module_set)
            max_module_count = math.max(max_module_count, module_kinds)
        end
    end

    local used_width = 0
    used_width = used_width + (frame_border_size * 2)  -- border on both sides
    used_width = used_width + (table_padding * 2)  -- padding on both sides
    used_width = used_width + (table_spacing * 4)  -- 5 columns -> 4 spaces
    used_width = used_width + recipe_and_check_width  -- constant
    -- Add up machines button, module buttons, and spacing for them
    used_width = used_width + button_width + (max_module_count * button_width) + (max_module_count * button_spacing)

    -- Calculate the remaining width and divide by the amount a button takes up
    local available_columns = (frame_width - used_width + button_spacing) / (button_width + button_spacing)
    return math.floor(available_columns)  -- amount is floored as to not cause a horizontal scrollbar
end

local function determine_table_height(lines, column_counts)
    local total_height = 0
    for _, line in pairs(lines) do
        local items_height = 0
        for column, count in pairs(column_counts) do
            local column_height = math.ceil(line[column].count / count)
            items_height = math.max(items_height, column_height)
        end

        local machines_height = (line.beacon ~= nil) and 2 or 1
        total_height = total_height + math.max(machines_height, items_height)
    end
    return total_height
end

local function determine_column_counts(lines, available_columns)
    local column_counts = {Ingredient = 1, Product = 1, Byproduct = 0}  -- ordered by priority
    available_columns = available_columns - 2  -- two buttons are already assigned

    local previous_height, increment = math.huge, 1
    while available_columns > 0 do
        local table_heights, minimal_height = {}, math.huge

        for column, count in pairs(column_counts) do
            local potential_column_counts = fancytable.shallow_copy(column_counts)
            potential_column_counts[column] = count + increment
            local new_height = determine_table_height(lines, potential_column_counts)
            table_heights[column] = new_height
            minimal_height = math.min(minimal_height, new_height)
        end

        -- If increasing any column by 1 doesn't change the height, try incrementing by more
        --   until height is decreased, or no columns are available anymore
        if not (minimal_height < previous_height) and increment < available_columns then
            increment = increment + 1
        else
            for column, height in pairs(table_heights) do
                if available_columns > 0 and height == minimal_height then
                    column_counts[column] = column_counts[column] + 1
                    available_columns = available_columns - 1
                    break
                end
            end

            previous_height, increment = minimal_height, 1  -- reset these
        end
    end

    return column_counts
end


local function add_checkmark_button(parent_flow, line, relevant_line)
    parent_flow.add{type="checkbox", state=relevant_line.done, mouse_button_filter={"left"},
      tags={mod="fp", on_gui_checked_state_changed="checkmark_compact_line", line_id=line.id}}
end

local function add_recipe_button(parent_flow, line, relevant_line, metadata)
    local recipe_proto = relevant_line.recipe.proto
    local style = (line.subfloor ~= nil) and "flib_slot_button_blue_small" or "flib_slot_button_default_small"
    style = (line.done) and "flib_slot_button_grayscale_small" or style
    local tooltip = {"", {"fp.tt_title", recipe_proto.localised_name}, metadata.recipe_tutorial_tt}

    parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_compact_recipe", line_id=line.id},
      sprite=recipe_proto.sprite, tooltip=tooltip, style=style, mouse_button_filter={"left-and-right"}}
end

local function add_modules_flow(parent_flow, parent_type, line, metadata)
    for _, module in ipairs(ModuleSet.get_in_order(line[parent_type].module_set)) do
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", {"fp.tt_title", module.proto.localised_name}, number_line, metadata.module_tutorial_tt}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        parent_flow.add{type="sprite-button", sprite=module.proto.sprite, tooltip=tooltip,
          tags={mod="fp", on_gui_click="act_on_compact_module", line_id=line.id, module_id=module.id,
            parent_type=parent_type}, number=module.amount, style=style, mouse_button_filter={"left-and-right"}}
    end
end

local function add_machine_flow(parent_flow, line, metadata)
    if line.subfloor == nil then
        local machine_flow = parent_flow.add{type="flow", direction="horizontal"}
        local machine_proto = line.machine.proto

        local tooltip_count = ui_util.format_number(line.machine.count, 4)
        local machine_count = math.ceil(tooltip_count)  -- button count always rounded up here
        if machine_count == "0" and line.production_ratio > 0 then
            tooltip_count = "<0.0001"
            machine_count = "0.01"  -- shows up as 0.0 on the button
        end

        local plural_parameter = (machine_count == "1") and 1 or 2
        local number_line = {"", "\n", tooltip_count, " ", {"fp.pl_machine", plural_parameter}}
        local tooltip = {"", {"fp.tt_title", machine_proto.localised_name}, number_line, metadata.machine_tutorial_tt}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        machine_flow.add{type="sprite-button", sprite=machine_proto.sprite, number=machine_count,
          tooltip=tooltip, tags={mod="fp", on_gui_click="act_on_compact_machine", type="machine", line_id=line.id},
          style=style, mouse_button_filter={"left-and-right"}}

        add_modules_flow(machine_flow, "machine", line, metadata)
    end
end

local function add_beacon_flow(parent_flow, line, metadata)
    if line.subfloor == nil and line.beacon ~= nil then
        local beacon_flow = parent_flow.add{type="flow", direction="horizontal"}
        local beacon_proto = line.beacon.proto

        local plural_parameter = (line.beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"", "\n", line.beacon.amount, " ", {"fp.pl_beacon", plural_parameter}}
        local tooltip = {"", {"fp.tt_title", beacon_proto.localised_name}, number_line, metadata.beacon_tutorial_tt}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        beacon_flow.add{type="sprite-button", sprite=beacon_proto.sprite, number=line.beacon.amount,
          tooltip=tooltip, tags={mod="fp", on_gui_click="act_on_compact_beacon", type="beacon", line_id=line.id},
          style=style, mouse_button_filter={"left-and-right"}}

        add_modules_flow(beacon_flow, "beacon", line, metadata)
    end
end


local function add_item_flow(line, item_class, button_color, metadata)
    local column_count = metadata.column_counts[item_class]
    if column_count == 0 then metadata.parent.add{type="empty-widget"}; return end
    local item_table = metadata.parent.add{type="table", column_count=column_count}

    for _, item in ipairs(Line.get_in_order(line, item_class)) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata, item, nil, machine_count)
        if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", {"fp.tt_title", item.proto.localised_name}, number_line, metadata.item_tutorial_tt}
        local style = (line.done) and "flib_slot_button_grayscale_small"
          or "flib_slot_button_" .. button_color .. "_small"

        item_table.add{type="sprite-button", sprite=item.proto.sprite, number=amount, tooltip=tooltip,
          tags={mod="fp", on_gui_click="act_on_compact_item", line_id=line.id, class=item.class, item_id=item.id},
          style=style, mouse_button_filter={"left-and-right"}}

        ::skip_item::
    end

    if item_class == "Ingredient" and not line.subfloor and line.machine.fuel then
        local fuel, machine_count = line.machine.fuel, line.machine.count
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata, fuel, nil, machine_count)
        if amount == -1 then goto skip_fuel end  -- an amount of -1 means it was below the margin of error

        local name_line = {"fp.tt_title_with_note", fuel.proto.localised_name, {"fp.pl_fuel", 1}}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, metadata.item_tutorial_tt}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_cyan_small"

        item_table.add{type="sprite-button", sprite=fuel.proto.sprite, style=style, number=amount,
          tags={mod="fp", on_gui_click="act_on_compact_item", line_id=line.id, class="Fuel"},
          tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        ::skip_fuel::
    end
end


local function handle_recipe_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    local recipe = relevant_line.recipe

    if action == "open_subfloor" then
        if line.subfloor then
            ui_util.context.set_floor(player, line.subfloor)
            compact_subfactory.refresh(player)
        end

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "recipe", recipe.proto.name)
    end
end

local function handle_module_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor
    local parent_entity = line[tags.parent_type]
    local module = ModuleSet.get(parent_entity.module_set, tags.module_id)

    if action == "recipebook" then
        ui_util.open_in_recipebook(player, "item", module.proto.name)
    end
end

local function handle_machine_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        ui_util.put_entity_into_cursor(player, line, line.machine)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "entity", line.machine.proto.name)
    end
end

local function handle_beacon_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    -- I don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        ui_util.put_entity_into_cursor(player, line, line.beacon)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, "entity", line.beacon.proto.name)
    end
end

local function handle_item_click(player, tags, action)
    local context = data_util.get("context", player)
    local line = Floor.get(context.floor, "Line", tags.line_id)
    local item = (tags.class == "Fuel") and line.machine.fuel or Line.get(line, tags.class, tags.item_id)

    if action == "put_into_cursor" then
        ui_util.add_item_to_cursor_combinator(player, item.proto, item.amount)

    elseif action == "recipebook" then
        ui_util.open_in_recipebook(player, item.proto.type, item.proto.name)
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

    view_state.rebuild_state(player)  -- initializes the view_state
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
    local player_table = data_util.get("table", player)
    local compact_elements = player_table.ui_state.compact_elements
    local context = player_table.ui_state.context
    local subfactory = context.subfactory
    if not subfactory or not subfactory.valid then return end

    local current_level = subfactory.selected_floor.level
    local lines = Floor.get_in_order(context.floor, "Line")

    view_state.refresh(player, compact_elements.view_state_table)

    local attach_subfactory_products = player_table.preferences.attach_subfactory_products
    compact_elements.name_label.caption = Subfactory.tostring(subfactory, attach_subfactory_products, true)

    compact_elements.level_label.caption = {"fp.bold_label", {"", "-   ", {"fp.level"}, " ", current_level}}
    compact_elements.floor_up_button.enabled = (current_level > 1)
    compact_elements.floor_top_button.enabled = (current_level > 1)

    local production_table = compact_elements.production_table
    production_table.clear()

    -- Available columns for items only, as recipe and machines can't be 'compressed'
    local frame_width = compact_elements.compact_frame.style.maximal_width
    local available_columns = determine_available_columns(lines, frame_width)
    if available_columns < 2 then available_columns = 2 end  -- fix for too many modules or too high of a GUI scale
    local column_counts = determine_column_counts(lines, available_columns)

    local metadata = {
        parent = production_table,
        column_counts = column_counts,
        view_state_metadata = view_state.generate_metadata(player, subfactory, 4, true)
    }

    if data_util.get("preferences", player).tutorial_mode then
        local limitations = {archive_open = false, matrix_active = false}
        data_util.add_tutorial_tooltips(metadata, limitations, {
            recipe_tutorial_tt = "act_on_compact_recipe",
            module_tutorial_tt = "act_on_compact_module",
            machine_tutorial_tt = "act_on_compact_machine",
            beacon_tutorial_tt = "act_on_compact_beacon",
            item_tutorial_tt = "act_on_compact_item",
        })
    end

    for _, line in ipairs(lines) do -- build the individual lines
        local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
        if not relevant_line.active then goto skip_line end

        -- Recipe and Checkmark
        local recipe_flow = production_table.add{type="flow", direction="horizontal"}
        recipe_flow.style.vertical_align = "center"
        add_checkmark_button(recipe_flow, line, relevant_line)
        add_recipe_button(recipe_flow, line, relevant_line, metadata)

        -- Machine and Beacon
        local machines_flow = production_table.add{type="flow", direction="vertical"}
        add_machine_flow(machines_flow, line, metadata)
        add_beacon_flow(machines_flow, line, metadata)

        -- Products, Byproducts and Ingredients
        add_item_flow(line, "Product", "default", metadata)
        add_item_flow(line, "Byproduct", "red", metadata)
        add_item_flow(line, "Ingredient", "green", metadata)

        production_table.add{type="empty-widget", style="flib_horizontal_pusher"}

        ::skip_line::
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
            name = "act_on_compact_recipe",
            modifier_actions = {
                open_subfloor = {"left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_recipe_click
        },
        {
            name = "act_on_compact_module",
            modifier_actions = {
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_module_click
        },
        {
            name = "act_on_compact_machine",
            modifier_actions = {
                put_into_cursor = {"left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_machine_click
        },
        {
            name = "act_on_compact_beacon",
            modifier_actions = {
                put_into_cursor = {"left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_beacon_click
        },
        {
            name = "act_on_compact_item",
            modifier_actions = {
                put_into_cursor = {"left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_click
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "checkmark_compact_line",
            handler = (function(player, tags, _)
                local line = Floor.get(data_util.get("context", player).floor, "Line", tags.line_id)
                local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
                relevant_line.done = not relevant_line.done
                compact_subfactory.refresh(player)
            end)
        }
    }
}

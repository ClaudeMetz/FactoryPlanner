-- The main GUI parts for the compact dialog
local function determine_available_columns(floor, frame_width)
    local frame_border_size = 12
    local table_padding, table_spacing = 8, 12
    local recipe_and_check_width = 58
    local button_width, button_spacing = 36, 4

    local max_module_count = 0
    for line in floor:iterator() do
        if line.class == "Line" then
            local module_kinds = line.machine.module_set:count()
            max_module_count = math.max(max_module_count, module_kinds)
        end
        if line.beacon ~= nil then
            local module_kinds = line.beacon.module_set:count()
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

local function determine_table_height(floor, column_counts)
    local total_height = 0
    for line in floor:iterator() do
        local items_height = 0
        for column, count in pairs(column_counts) do
            local item_count = #line[column .. "s"]

            if line.class == "Line" then
                if column == "ingredient" and line.machine.fuel then item_count = item_count + 1 end
                local catalysts = line.recipe_proto.catalysts[column .. "s"]
                if catalysts then item_count = item_count + table_size(catalysts) end
            end

            local column_height = math.ceil(item_count / count)
            items_height = math.max(items_height, column_height)
        end

        local machines_height = (line.beacon ~= nil) and 2 or 1
        total_height = total_height + math.max(machines_height, items_height)
    end
    return total_height
end

local function determine_column_counts(floor, available_columns)
    local column_counts = {ingredient = 1, product = 1, byproduct = 0}  -- ordered by priority
    available_columns = available_columns - 2  -- two buttons are already assigned

    local previous_height, increment = math.huge, 1
    while available_columns > 0 do
        local table_heights, minimal_height = {}, math.huge

        for column, count in pairs(column_counts) do
            local potential_column_counts = ftable.shallow_copy(column_counts)
            potential_column_counts[column] = count + increment
            local new_height = determine_table_height(floor, potential_column_counts)
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
    local recipe_proto = relevant_line.recipe_proto
    local style = (line.class == "Floor") and "flib_slot_button_blue_small" or "flib_slot_button_default_small"
    style = (relevant_line.done) and "flib_slot_button_grayscale_small" or style
    local tooltip = (line.class == "Line") and {"", {"fp.tt_title", recipe_proto.localised_name}}
        or {"", {"fp.tt_title", recipe_proto.localised_name}}
    table.insert(tooltip, {"", "\n", metadata.action_tooltips["act_on_compact_recipe"]})

    local button = parent_flow.add{type="sprite-button", sprite=recipe_proto.sprite, style=style,
        tags={mod="fp", on_gui_click="act_on_compact_recipe", line_id=line.id, on_gui_hover="set_tooltip",
        context="compact_dialog"}, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
    metadata.tooltips[button.index] = tooltip
end

local function add_modules_flow(parent_flow, parent_type, line, metadata)
    for module in line[parent_type].module_set:iterator() do
        local quality_proto = module.quality_proto
        local title_line = (not quality_proto.always_show) and {"fp.tt_title", module.proto.localised_name}
            or {"fp.tt_title_with_note", module.proto.localised_name, quality_proto.rich_text}
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", title_line, number_line, "\n", metadata.action_tooltips["act_on_compact_module"]}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        local button = parent_flow.add{type="sprite-button", sprite=module.proto.sprite, style=style,
            tags={mod="fp", on_gui_click="act_on_compact_module", module_id=module.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}, quality=quality_proto.name,
            number=module.amount, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip
    end
end

local function add_machine_flow(parent_flow, line, metadata)
    if line.class == "Line" then
        local machine_flow = parent_flow.add{type="flow", direction="horizontal"}
        local machine, machine_proto = line.machine, line.machine.proto
        local quality_proto = machine.quality_proto

        local title_line = (not quality_proto.always_show) and {"fp.tt_title", machine_proto.localised_name}
            or {"fp.tt_title_with_note", machine_proto.localised_name, quality_proto.rich_text}
        local amount, tooltip_line = util.format.machine_count(machine.amount, true)
        local tooltip = {"", title_line, tooltip_line, "\n", metadata.action_tooltips["act_on_compact_machine"]}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        local button = machine_flow.add{type="sprite-button", sprite=machine_proto.sprite, number=amount, style=style,
            tags={mod="fp", on_gui_click="act_on_compact_machine", type="machine", line_id=line.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}, quality=quality_proto.name,
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        add_modules_flow(machine_flow, "machine", line, metadata)
    end
end

local function add_beacon_flow(parent_flow, line, metadata)
    if line.class == "Line" and line.beacon ~= nil then
        local beacon_flow = parent_flow.add{type="flow", direction="horizontal"}
        local beacon, beacon_proto = line.beacon, line.beacon.proto
        local quality_proto = beacon.quality_proto

        local title_line = (not quality_proto.always_show) and {"fp.tt_title", beacon_proto.localised_name}
            or {"fp.tt_title_with_note", beacon_proto.localised_name, quality_proto.rich_text}
        local plural_parameter = (beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"", "\n", beacon.amount, " ", {"fp.pl_beacon", plural_parameter}}
        local tooltip = {"", title_line, number_line, "\n", metadata.action_tooltips["act_on_compact_beacon"]}
        local style = (line.done) and "flib_slot_button_grayscale_small" or "flib_slot_button_default_small"

        local button = beacon_flow.add{type="sprite-button", sprite=beacon_proto.sprite, number=beacon.amount,
            tags={mod="fp", on_gui_click="act_on_compact_beacon", type="beacon", line_id=line.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}, quality=quality_proto.name, style=style,
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        add_modules_flow(beacon_flow, "beacon", line, metadata)
    end
end


local function add_item_flow(line, relevant_line, item_category, button_color, metadata, item_buttons)
    local column_count = metadata.column_counts[item_category]
    if column_count == 0 then metadata.parent.add{type="empty-widget"}; return end
    local item_table = metadata.parent.add{type="table", column_count=column_count}

    for index, item in pairs(line[item_category .. "s"]) do
        local proto, type = item.proto, item.proto.type
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (line.class == "Line") and line.machine.amount or nil
        local amount, number_tooltip = item_views.process_item(metadata.player, item, nil, machine_count)
        if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error

        local style, enabled = "flib_slot_button_" .. button_color .. "_small"
        if relevant_line.done then style = "flib_slot_button_grayscale_small" end
        local name_line, temperature_line = {"", {"fp.tt_title", {"", proto.localised_name}}}, ""

        if type == "entity" then
            style = (relevant_line.done) and "flib_slot_button_disabled_grayscale_small"
                or "flib_slot_button_disabled_small"
        elseif type == "fluid" and item_category == "ingredient" and line.class ~= "Floor" then
            local temperature_data = line.temperature_data[proto.name]   -- exists for any fluid ingredient
            table.insert(name_line, temperature_data.annotation)

            local temperature = line.temperatures[proto.name]
            if temperature == nil then
                style = "flib_slot_button_purple_small"
                temperature_line = {"fp.no_temperature_configured"}
            else
                temperature_line = {"fp.configured_temperature", temperature}
            end
        end

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, temperature_line, number_line, "\n",
            metadata.action_tooltips["act_on_compact_item"]}

        local button = item_table.add{type="sprite-button", sprite=proto.sprite, number=amount,
            tags={mod="fp", on_gui_click="act_on_compact_item", line_id=line.id, item_category=item_category .. "s",
            item_index=index, on_gui_hover="hover_compact_item", on_gui_leave="leave_compact_item",
            context="compact_dialog"}, style=style, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        item_buttons[type] = item_buttons[type] or {}
        item_buttons[type][proto.name] = item_buttons[type][proto.name] or {}
        table.insert(item_buttons[type][proto.name], {button=button, proper_style=style, size="_small"})

        ::skip_item::
    end

    if line.class == "Floor" then return end

    if item_category == "product" or item_category == "ingredient" then
        for _, item in pairs(line.recipe_proto.catalysts[item_category .. "s"]) do
            local item_proto = prototyper.util.find("items", item.name, item.type)  --[[@as FPItemPrototype]]

            local amount, number_tooltip = item_views.process_item(metadata.player, {proto=item_proto},
                (item.amount * line.production_ratio), line.machine.amount)
            local title_line = {"fp.tt_title_with_note", item_proto.localised_name, {"fp.catalyst"}}
            local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""

            item_table.add{type="sprite-button", sprite=item_proto.sprite, number=amount,
                tooltip={"", title_line, number_line}, style="flib_slot_button_blue_small"}
        end
    end

    if item_category == "ingredient" and line.machine.fuel then
        local fuel, machine_count = line.machine.fuel, line.machine.amount
        local amount, number_tooltip = item_views.process_item(metadata.player, fuel, nil, machine_count)
        if amount == -1 then goto skip_fuel end  -- an amount of -1 means it was below the margin of error

        local style = "flib_slot_button_cyan_small"
        local name_line, temperature_line = {"fp.tt_title_with_note", fuel.proto.localised_name, {"fp.pu_fuel", 1}}, ""

        if fuel.proto.type == "fluid" then
            local temperature_data = fuel.temperature_data   -- exists for any fluid fuel
            table.insert(name_line, temperature_data.annotation)

            if fuel.temperature == nil then
                style = "flib_slot_button_purple_small"
                temperature_line = {"fp.no_temperature_configured"}
            else
                temperature_line = {"fp.configured_temperature", fuel.temperature}
            end
        end

        style = (relevant_line.done) and "flib_slot_button_grayscale_small" or style
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, temperature_line, number_line, "\n",
            metadata.action_tooltips["act_on_compact_item"]}

        local button = item_table.add{type="sprite-button", sprite=fuel.proto.sprite, style=style, number=amount,
            tags={mod="fp", on_gui_click="act_on_compact_item", fuel_id=fuel.id, on_gui_hover="hover_compact_item",
            on_gui_leave="leave_compact_item", context="compact_dialog"}, mouse_button_filter={"left-and-right"},
            raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        local type, name = fuel.proto.type, fuel.proto.name
        item_buttons[type] = item_buttons[type] or {}
        item_buttons[type][name] = item_buttons[type][name] or {}
        table.insert(item_buttons[type][name], {button=button, proper_style=style, size="_small"})

        ::skip_fuel::
    end
end


local function refresh_compact_header(player, factory)
    local player_table = util.globals.player_table(player)
    local compact_elements = player_table.ui_state.compact_elements

    local attach_factory_products = player_table.preferences.attach_factory_products
    compact_elements.name_label.caption = factory:tostring(attach_factory_products, true)

    local current_floor = util.context.get(player, "Floor")
    compact_elements.level_label.caption = {"fp.bold_label", {"", "-   ", {"fp.level"}, " ", current_floor.level}}
    compact_elements.floor_up_button.enabled = (current_floor.level > 1)
    compact_elements.floor_top_button.enabled = (current_floor.level > 1)

    local compact_ingredients = player_table.preferences.compact_ingredients
    compact_elements.ingredient_toggle.toggled = compact_ingredients
    compact_elements.ingredient_toggle.sprite = (compact_ingredients) and "fp_dropup" or "utility/dropdown"

    local ingredients_frame = compact_elements.ingredients_frame
    ingredients_frame.visible = compact_ingredients

    ingredients_frame.clear()

    local frame_width = compact_elements.compact_frame.style.maximal_width
    local available_space = frame_width - (2*12)  -- 12px padding on both sides
    local column_count = math.floor(available_space / 40)
    local padding = (available_space - (column_count * 40)) / 2
    ingredients_frame.style.padding = {0, padding}

    local item_frame = ingredients_frame.add{type="frame", style="slot_button_deep_frame"}
    local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}

    local item_buttons = compact_elements.item_buttons

    local show_floor_items = player_table.preferences.show_floor_items
    local relevant_floor = (show_floor_items) and current_floor or factory.top_floor
    for index, ingredient in pairs(relevant_floor.ingredients) do
        local amount, number_tooltip = item_views.process_item(player, ingredient, nil, nil)
        if amount == -1 then goto skip_ingredient end  -- an amount of -1 means it was below the margin of error

        local name_line = {"fp.tt_title", ingredient.proto.localised_name}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, "\n", MODIFIER_ACTIONS["act_on_compact_item"].tooltip}
        local style = "flib_slot_button_default"

        local button = table_items.add{type="sprite-button", number=amount, tooltip=tooltip,
            tags={mod="fp", on_gui_click="act_on_compact_ingredient", floor_id=relevant_floor.id, item_index=index,
            on_gui_hover="hover_compact_item", on_gui_leave="leave_compact_item", context="compact_dialog"},
            sprite=ingredient.proto.sprite, style=style, mouse_button_filter={"left-and-right"},
            raise_hover_events=true}
        player_table.ui_state.tooltips[button.index] = tooltip

        local type, name = ingredient.proto.type, ingredient.proto.name
        item_buttons[type] = item_buttons[type] or {}
        item_buttons[type][name] = item_buttons[type][name] or {}
        table.insert(item_buttons[type][name], {button=button, proper_style=style, size=""})

        ::skip_ingredient::
    end
end

local function refresh_compact_production(player, factory)
    local ui_state = util.globals.ui_state(player)
    local compact_elements = ui_state.compact_elements

    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local production_table = compact_elements.production_table
    production_table.clear()

    -- Available columns for items only, as recipe and machines can't be 'compressed'
    local frame_width = compact_elements.compact_frame.style.maximal_width
    local available_columns = determine_available_columns(floor, frame_width)
    if available_columns < 2 then available_columns = 2 end  -- fix for too many modules or too high of a GUI scale
    local column_counts = determine_column_counts(floor, available_columns)

    local metadata = {
        player = player,
        parent = production_table,
        column_counts = column_counts,
        tooltips = ui_state.tooltips.compact_dialog,
        action_tooltips = {
            act_on_compact_recipe = MODIFIER_ACTIONS["act_on_compact_recipe"].tooltip,
            act_on_compact_module = MODIFIER_ACTIONS["act_on_compact_module"].tooltip,
            act_on_compact_machine = MODIFIER_ACTIONS["act_on_compact_machine"].tooltip,
            act_on_compact_beacon = MODIFIER_ACTIONS["act_on_compact_beacon"].tooltip,
            act_on_compact_item = MODIFIER_ACTIONS["act_on_compact_item"].tooltip
        }
    }

    for line in floor:iterator() do -- build the individual lines
        local relevant_line = (line.class == "Floor") and line.first or line  --[[@as Line]]
        if not relevant_line.active or not relevant_line:get_surface_compatibility().overall
                or (not factory.matrix_free_items and relevant_line.production_type == "consume") then
            goto skip_line
        end

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
        add_item_flow(line, relevant_line, "product", "default", metadata, compact_elements.item_buttons)
        add_item_flow(line, relevant_line, "byproduct", "red", metadata, compact_elements.item_buttons)
        add_item_flow(line, relevant_line, "ingredient", "green", metadata, compact_elements.item_buttons)

        production_table.add{type="empty-widget", style="flib_horizontal_pusher"}

        ::skip_line::
    end
end

local function refresh_compact_factory(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    if not factory or not factory.valid then return end

    local ui_state = util.globals.ui_state(player)
    ui_state.tooltips.compact_dialog = {}
    ui_state.compact_elements.item_buttons = {}

    refresh_compact_header(player, factory)
    refresh_compact_production(player, factory)
end

local function build_compact_factory(player)
    local ui_state = util.globals.ui_state(player)
    local compact_elements = ui_state.compact_elements
    local content_flow = compact_elements.content_flow

    -- Header frame
    local subheader = content_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    subheader.style.padding = 4

    -- View state
    local container_views = subheader.add{type="flow", direction="horizontal"}
    container_views.style.padding = {4, 4, 0, 0}
    container_views.add{type="empty-widget", style="flib_horizontal_pusher"}

    local flow_views = container_views.add{type="flow", direction="horizontal"}
    compact_elements["views_flow"] = flow_views

    local line = subheader.add{type="line", direction="horizontal"}
    line.style.padding = {2, 0, 6, 0}

    -- Flow navigation
    local flow_navigation = subheader.add{type="flow", direction="horizontal"}
    flow_navigation.style.vertical_align = "center"
    flow_navigation.style.margin = {4, 4, 4, 8}

    local label_name = flow_navigation.add{type="label"}
    label_name.style.font = "heading-2"
    label_name.style.horizontally_squashable = true
    compact_elements["name_label"] = label_name

    local label_level = flow_navigation.add{type="label"}
    label_level.style.margin = {0, 6, 0, 6}
    compact_elements["level_label"] = label_level

    local button_floor_up = flow_navigation.add{type="sprite-button", sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, tags={mod="fp", on_gui_click="change_compact_floor", destination="up"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    compact_elements["floor_up_button"] = button_floor_up

    local button_floor_top = flow_navigation.add{type="sprite-button", sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, tags={mod="fp", on_gui_click="change_compact_floor", destination="top"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_top.style.padding = {3, 2, 1, 2}
    compact_elements["floor_top_button"] = button_floor_top

    flow_navigation.add{type="empty-widget", style="flib_horizontal_pusher"}

    local button_ingredients = flow_navigation.add{type="sprite-button", auto_toggle=true,
        tooltip={"fp.compact_toggle_ingredients"}, tags={mod="fp", on_gui_click="toggle_compact_ingredients"},
        style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_ingredients.style.padding = 0
    compact_elements["ingredient_toggle"] = button_ingredients

    -- Ingredients frame
    local ingredients_frame = content_flow.add{type="frame", direction="vertical",
        style="inside_deep_frame"}
    compact_elements["ingredients_frame"] = ingredients_frame

    -- Production table
    local production_frame = content_flow.add{type="frame", direction="vertical",
        style="inside_deep_frame"}
    local scroll_pane_production = production_frame.add{type="scroll-pane",
        style="flib_naked_scroll_pane_no_padding"}
    scroll_pane_production.horizontal_scroll_policy = "never"
    scroll_pane_production.style.horizontally_stretchable = true

    local table_production = scroll_pane_production.add{type="table", column_count=6, style="fp_table_production"}
    table_production.vertical_centering = false
    table_production.style.horizontal_spacing = 12
    table_production.style.vertical_spacing = 8
    table_production.style.padding = {4, 8}
    compact_elements["production_table"] = table_production

    refresh_compact_factory(player)
end


local function handle_ingredient_click(player, tags, action)
    local floor = OBJECT_INDEX[tags.floor_id]
    local item = floor.ingredients[tags.item_index]

    if action == "add_to_cursor" then
        util.cursor.handle_item_click(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        local name = (item.proto.temperature) and item.proto.base_name or item.proto.name
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end

local function handle_recipe_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]
    local relevant_line = (line.class == "Floor") and line.first or line

    if action == "open_subfloor" then
        if line.class == "Floor" then
            util.context.set(player, line)
            refresh_compact_factory(player)
        end
    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["recipe"][relevant_line.recipe_proto.name])
    end
end

local function handle_module_click(player, tags, action)
    local module = OBJECT_INDEX[tags.module_id]

    if action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["item"][module.proto.name])
    end
end

local function handle_machine_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]
    -- We don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "add_to_cursor" then
        util.cursor.set_entity(player, line, line.machine)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["entity"][line.machine.proto.name])
    end
end

local function handle_beacon_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]
    -- We don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "add_to_cursor" then
        util.cursor.set_entity(player, line, line.beacon)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["entity"][line.beacon.proto.name])
    end
end

local function handle_item_click(player, tags, action)
    local item = (tags.fuel_id) and OBJECT_INDEX[tags.fuel_id]
        or OBJECT_INDEX[tags.line_id][tags.item_category][tags.item_index]

    if action == "add_to_cursor" then
        if item.proto.type == "entity" then return end
        util.cursor.handle_item_click(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        local name = item.proto.name
        if item.proto.type == "entity" then name = name:gsub("custom%-", "")
        elseif item.proto.temperature then name = item.proto.base_name end
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end

local function handle_hover_change(player, tags, event)
    local proto = nil
    if tags.floor_id then
        proto = OBJECT_INDEX[tags.floor_id].ingredients[tags.item_index].proto
    elseif tags.fuel_id then
        proto = OBJECT_INDEX[tags.fuel_id].proto
    else
        proto = OBJECT_INDEX[tags.line_id][tags.item_category][tags.item_index].proto
    end

    local compact_elements = util.globals.ui_state(player).compact_elements
    local relevant_buttons = compact_elements.item_buttons[proto.type][proto.name]
    for _, button_data in pairs(relevant_buttons) do
        button_data.button.style = (event.name == defines.events.on_gui_hover)
            and "flib_slot_button_pink" .. button_data.size or button_data.proper_style
    end
end


-- ** EVENTS **
local factory_listeners = {}

factory_listeners.gui = {
    on_gui_click = {
        {
            name = "change_compact_floor",
            handler = (function(player, tags, _)
                local floor_changed = util.context.ascend_floors(player, tags.destination)
                if floor_changed then refresh_compact_factory(player) end
            end)
        },
        {
            name = "toggle_compact_ingredients",
            handler = (function(player, _, event)
                local preferences = util.globals.preferences(player)
                preferences.compact_ingredients = not preferences.compact_ingredients

                local compact_elements = util.globals.ui_state(player).compact_elements
                local sprite = (preferences.compact_ingredients) and "fp_dropup" or "utility/dropdown"
                compact_elements.ingredient_toggle.sprite = sprite
                compact_elements.ingredients_frame.visible = preferences.compact_ingredients
            end)
        },
        {
            name = "act_on_compact_ingredient",
            actions_table = {
                add_to_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_ingredient_click
        },
        {
            name = "act_on_compact_recipe",
            actions_table = {
                open_subfloor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_recipe_click
        },
        {
            name = "act_on_compact_module",
            actions_table = {
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_module_click
        },
        {
            name = "act_on_compact_machine",
            actions_table = {
                add_to_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_machine_click
        },
        {
            name = "act_on_compact_beacon",
            actions_table = {
                add_to_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_beacon_click
        },
        {
            name = "act_on_compact_item",
            actions_table = {
                add_to_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_item_click
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "checkmark_compact_line",
            handler = (function(player, tags, _)
                local line = OBJECT_INDEX[tags.line_id]
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.done = not relevant_line.done
                refresh_compact_factory(player)
            end)
        }
    },
    on_gui_hover = {
        {
            name = "hover_compact_item",
            handler = (function(player, tags, event)
                handle_hover_change(player, tags, event)
                main_dialog.set_tooltip(player, event.element)
            end)
        }
    },
    on_gui_leave = {
        {
            name = "leave_compact_item",
            handler = handle_hover_change
        }
    }
}

factory_listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "compact_factory" then
            build_compact_factory(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        if event.trigger == "compact_factory" then
            refresh_compact_factory(player)
        end
    end)
}


-- ** UTIL **
-- Set frame dimensions in a relative way, taking player resolution and scaling into account
local function set_compact_frame_dimensions(player, frame)
    local scaled_resolution = util.gui.calculate_scaled_resolution(player)
    local compact_width_percentage = util.globals.preferences(player).compact_width_percentage
    frame.style.width = scaled_resolution.width * (compact_width_percentage / 100)
    frame.style.maximal_height = scaled_resolution.height * 0.8
end

local function set_compact_frame_location(player, frame)
    local scale = player.display_scale
    frame.location = {10 * scale, 63 * scale}
end


-- ** TOP LEVEL **
compact_dialog = {}

function compact_dialog.rebuild(player, default_visibility)
    local ui_state = util.globals.ui_state(player)

    local interface_visible = default_visibility
    local compact_frame = ui_state.compact_elements.compact_frame
    -- Delete the existing interface if there is one
    if compact_frame ~= nil then
        if compact_frame.valid then
            interface_visible = compact_frame.visible
            compact_frame.destroy()
        end

        ui_state.compact_elements = {}  -- reset all compact element references
    end

    local frame_compact_dialog = player.gui.screen.add{type="frame", direction="vertical",
        visible=interface_visible, name="fp_frame_compact_dialog"}
    set_compact_frame_location(player, frame_compact_dialog)
    set_compact_frame_dimensions(player, frame_compact_dialog)
    ui_state.compact_elements["compact_frame"] = frame_compact_dialog

    -- Title bar
    local flow_title_bar = frame_compact_dialog.add{type="flow", direction="horizontal", style="frame_header_flow",
        tags={mod="fp", on_gui_click="place_compact_dialog"}}
    flow_title_bar.drag_target = frame_compact_dialog

    flow_title_bar.add{type="sprite-button", style="fp_button_frame", toggled=true,
        tags={mod="fp", on_gui_click="switch_to_main_view"}, tooltip={"fp.switch_to_main_view"},
        sprite="fp_pin", mouse_button_filter={"left"}}

    local button_calculator = flow_title_bar.add{type="sprite-button", sprite="fp_calculator",
        tooltip={"fp.open_calculator"}, style="fp_button_frame", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="open_calculator_dialog"}}
    button_calculator.style.padding = -3

    flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}
    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="fp_label_frame_title",
        ignored_by_interaction=true}
    flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
        ignored_by_interaction=true}

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="close_compact_dialog"},
        sprite="utility/close", tooltip={"fp.close_interface"}, style="fp_button_frame", mouse_button_filter={"left"}}
    button_close.style.padding = 1

    local flow_content = frame_compact_dialog.add{type="flow", direction="vertical"}
    flow_content.style.vertical_spacing = 8
    ui_state.compact_elements["content_flow"] = flow_content

    item_views.rebuild_data(player)
    util.raise.build(player, "compact_factory", nil)
    item_views.rebuild_interface(player)

    return frame_compact_dialog
end

function compact_dialog.toggle(player)
    local frame_compact_dialog = util.globals.ui_state(player).compact_elements.compact_frame
    -- Doesn't set player.opened so other GUIs like the inventory can be opened when building

    if frame_compact_dialog == nil or not frame_compact_dialog.valid then
        compact_dialog.rebuild(player, true)  -- refreshes on its own
    else
        local new_dialog_visibility = not frame_compact_dialog.visible
        frame_compact_dialog.visible = new_dialog_visibility

        if new_dialog_visibility then refresh_compact_factory(player) end
    end
end

function compact_dialog.is_in_focus(player)
    local frame_compact_dialog = util.globals.ui_state(player).compact_elements.compact_frame
    return (frame_compact_dialog ~= nil and frame_compact_dialog.valid and frame_compact_dialog.visible)
end


-- ** EVENTS **
local dialog_listeners = {}

dialog_listeners.gui = {
    on_gui_click = {
        {
            name = "switch_to_main_view",
            handler = (function(player, _, _)
                util.globals.ui_state(player).compact_view = false
                compact_dialog.toggle(player)

                main_dialog.toggle(player)
                util.raise.refresh(player, "production")
            end)
        },
        {
            name = "close_compact_dialog",
            handler = (function(player, _, _)
                compact_dialog.toggle(player)
            end)
        },
        {
            name = "place_compact_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local frame_compact_dialog = util.globals.ui_state(player).compact_elements.compact_frame
                    set_compact_frame_location(player, frame_compact_dialog)
                end
            end)
        }
    }
}

dialog_listeners.misc = {
    on_player_display_resolution_changed = (function(player, _)
        compact_dialog.rebuild(player, false)
    end),

    on_player_display_scale_changed = (function(player, _)
        compact_dialog.rebuild(player, false)
    end),

    on_lua_shortcut = (function(player, event)
        if event.prototype_name == "fp_open_interface" and util.globals.ui_state(player).compact_view then
            compact_dialog.toggle(player)
        end
    end),

    fp_toggle_interface = (function(player, _)
        if util.globals.ui_state(player).compact_view then compact_dialog.toggle(player) end
    end)
}

return { factory_listeners, dialog_listeners }

-- The main GUI parts for the compact dialog
---@param floor Floor
---@param frame_width int32
---@return integer
local function determine_available_columns(floor, frame_width)
    local frame_border_size = 12
    local table_padding, table_spacing = 8, 12
    local recipe_and_check_width = 58
    local button_width, button_spacing = 36, 4

    local max_module_count = 0
    for line in floor:iterator() do
        if line.class == "Line" then
            local module_kinds = line.machine.module_set:count()
            max_module_count = math.max(max_module_count, module_kinds)  ---@as integer
        end
        if line.beacon ~= nil then
            local module_kinds = line.beacon.module_set:count()
            max_module_count = math.max(max_module_count, module_kinds)  ---@as integer
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

---@param floor Floor
---@param column_counts CompactColumnCounts
---@return number
local function determine_table_height(floor, column_counts)
    local total_height = 0
    for line in floor:iterator() do
        local items_height = 0
        for column, count in pairs(column_counts) do
            local item_count = #line[column]

            if line.class == "Line" then
                if column == "ingredients" and line.machine.fuel then item_count = item_count + 1 end
                local recipe_proto = line.recipe.proto  ---@as FPRecipePrototype
                local catalysts = recipe_proto.catalysts[column--[[@as "ingredients" | "products"]]]
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

---@alias CompactColumnCounts {ingredients: integer, products: integer, byproducts: integer}

---@param floor Floor
---@param available_columns integer
---@return CompactColumnCounts
local function determine_column_counts(floor, available_columns)
    local column_counts = {ingredients = 1, products = 1, byproducts = 0}  -- ordered by priority
    local remaining_columns = available_columns - 2  -- two buttons are already assigned

    local previous_height, increment = 2^53, 1
    while remaining_columns > 0 do
        local table_heights, minimal_height = {}, 2^53

        for column, count in pairs(column_counts) do
            local potential_column_counts = lib.flib.shallow_copy(column_counts)
            potential_column_counts[column] = count + increment
            local new_height = determine_table_height(floor, potential_column_counts)
            table_heights[column] = new_height
            minimal_height = math.min(minimal_height, new_height)  ---@as integer
        end

        -- If increasing any column by 1 doesn't change the height, try incrementing by more
        --   until height is decreased, or no columns are available anymore
        if not (minimal_height < previous_height) and increment < remaining_columns then
            increment = increment + 1
        else
            for column, height in pairs(table_heights) do
                if remaining_columns > 0 and height == minimal_height then
                    column_counts[column] = column_counts[column] + 1
                    remaining_columns = remaining_columns - 1
                    break
                end
            end

            previous_height, increment = minimal_height, 1  -- reset these
        end
    end

    return column_counts
end

---@param parent_flow LuaGuiElement
---@param line LineObject
---@param relevant_line Line
local function add_checkmark_button(parent_flow, line, relevant_line)
    ---@class CheckmarkCompactLineTags
    ---@field line_id ObjectID
    local tags = {mod="fp", on_gui_checked_state_changed="checkmark_compact_line", line_id=line.id}
    parent_flow.add{type="checkbox", tags=tags, state=relevant_line.done, mouse_button_filter={"left"}}
end

---@param parent_flow LuaGuiElement
---@param line LineObject
---@param relevant_line Line
---@param metadata CompactMetadata
local function add_recipe_button(parent_flow, line, relevant_line, metadata)
    local style = (line.class == "Floor") and "fflib_slot_button_blue_small" or "fflib_slot_button_default_small"

    local note = ""  ---@type LocalisedString
    if relevant_line.done then
        if line.class == "Floor" and line--[[@as Floor]]:any_lines_not_marked_done() then
            style = "fflib_slot_button_orange_small"
            note = {"fp.lines_not_marked_done"}
        else
            style = "fflib_slot_button_grayscale_small"
        end
    end

    local recipe_proto = relevant_line.recipe.proto
    local tooltip = {"", {"fp.tt_title", recipe_proto.localised_name}, note,
        "\n", metadata.action_tooltips["act_on_compact_recipe"]}

    ---@class ActOnCompactRecipeTags
    ---@field line_id ObjectID
    ---@field context "compact_dialog"
    local tags = {mod="fp", on_gui_click="act_on_compact_recipe", line_id=line.id, on_gui_hover="set_tooltip",
        context="compact_dialog"}
    local button = parent_flow.add{type="sprite-button", tags=tags, sprite=recipe_proto.sprite, style=style,
        mouse_button_filter={"left-and-right"}, raise_hover_events=true}
    metadata.tooltips[button.index] = tooltip
end

---@param parent_flow LuaGuiElement
---@param line Line
---@param module_set ModuleSet
---@param metadata CompactMetadata
local function add_modules_flow(parent_flow, line, module_set, metadata)
    for module in module_set:iterator() do
        local quality_proto = module.quality_proto
        local title_line = (not quality_proto.always_show) and {"fp.tt_title", module.proto.localised_name}
            or {"fp.tt_title_with_note", module.proto.localised_name, quality_proto.rich_text}
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", title_line, number_line, "\n", metadata.action_tooltips["act_on_compact_module"]}
        local style = (line.done) and "fflib_slot_button_grayscale_small" or "fflib_slot_button_default_small"

        ---@class ActOnCompactModuleTags
        ---@field module_id ObjectID
        ---@field context "compact_dialog"
        local tags = {mod="fp", on_gui_click="act_on_compact_module", module_id=module.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}
        local button = parent_flow.add{type="sprite-button", tags=tags, sprite=module.proto.sprite, style=style,
            quality=quality_proto.name, number=module.amount, mouse_button_filter={"left-and-right"},
            raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip
    end
end

---@param parent_flow LuaGuiElement
---@param line LineObject
---@param metadata CompactMetadata
local function add_machine_flow(parent_flow, line, metadata)
    if line.class == "Line" then  ---@cast line Line
        local machine_flow = parent_flow.add{type="flow", direction="horizontal"}
        local machine, machine_proto = line.machine, line.machine.proto
        local quality_proto = machine.quality_proto

        local title_line = (not quality_proto.always_show) and {"fp.tt_title", machine_proto.localised_name}
            or {"fp.tt_title_with_note", machine_proto.localised_name, quality_proto.rich_text}
        local amount, tooltip_line = lib.format.machine_amount(machine.amount, true)
        local tooltip = {"", title_line, tooltip_line, "\n", metadata.action_tooltips["act_on_compact_machine"]}
        local style = (line.done) and "fflib_slot_button_grayscale_small" or "fflib_slot_button_default_small"

        ---@class ActOnCompactMachineTags
        ---@field line_id ObjectID
        ---@field context "compact_dialog"
        local tags = {mod="fp", on_gui_click="act_on_compact_machine", line_id=line.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}
        local button = machine_flow.add{type="sprite-button", tags=tags, sprite=machine_proto.sprite, number=amount,
            style=style, quality=quality_proto.name, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        add_modules_flow(machine_flow, line, machine.module_set, metadata)
    end
end

---@param parent_flow LuaGuiElement
---@param line LineObject
---@param metadata CompactMetadata
local function add_beacon_flow(parent_flow, line, metadata)
    if line.class == "Line" and line.beacon ~= nil then  ---@cast line Line
        local beacon_flow = parent_flow.add{type="flow", direction="horizontal"}
        local beacon, beacon_proto = line.beacon, line.beacon.proto
        local quality_proto = beacon.quality_proto

        local title_line = (not quality_proto.always_show) and {"fp.tt_title", beacon_proto.localised_name}
            or {"fp.tt_title_with_note", beacon_proto.localised_name, quality_proto.rich_text}
        local number_line = {"", "\n", beacon.amount, " ", {"fp.pl_beacon", beacon.amount}}
        local tooltip = {"", title_line, number_line, "\n", metadata.action_tooltips["act_on_compact_beacon"]}
        local style = (line.done) and "fflib_slot_button_grayscale_small" or "fflib_slot_button_default_small"

        ---@class ActOnCompactBeaconTags
        ---@field line_id ObjectID
        ---@field context "compact_dialog"
        local tags = {mod="fp", on_gui_click="act_on_compact_beacon", line_id=line.id,
            on_gui_hover="set_tooltip", context="compact_dialog"}
        local button = beacon_flow.add{type="sprite-button", tags=tags, sprite=beacon_proto.sprite, style=style,
            number=beacon.amount, quality=quality_proto.name, mouse_button_filter={"left-and-right"},
            raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        add_modules_flow(beacon_flow, line, beacon.module_set, metadata)
    end
end

---@param line LineObject
---@param relevant_line Line
---@param item_category "products" | "byproducts" | "ingredients"
---@param button_color string
---@param metadata CompactMetadata
---@param item_buttons table
local function add_item_flow(line, relevant_line, item_category, button_color, metadata, item_buttons)
    local column_count = metadata.column_counts[item_category]
    if column_count == 0 then metadata.parent.add{type="empty-widget"}; return end
    local item_table = metadata.parent.add{type="table", column_count=column_count}

    local first_special_index = nil  -- place for fuel to slot in
    for index, item in pairs(line[item_category]) do
        local proto, type = item.proto, item.proto.type

        local amount, number_tooltip = nil, nil
        button_color = (relevant_line.done) and "grayscale" or button_color
        local name_line = {"", {"fp.tt_title", {"", proto.localised_name}}}
        local action_line, temperature_line = "", ""  ---@type LocalisedString, LocalisedString

        ---@class ActOnCompactItemTags
        ---@field line_id ObjectID
        ---@field item_category "products" | "byproducts" | "ingredients"
        ---@field item_index integer
        ---@field context "compact_dialog"
        local tags = {mod="fp", line_id=line.id, item_category=item_category, item_index=index,
            on_gui_hover="hover_compact_item", on_gui_leave="leave_compact_item", context="compact_dialog"}

        if type == "entity" and proto.special then
            amount = lib.format.button_number(item.amount)
            number_tooltip = lib.format.special_tooltip(proto.name, item.amount)
            if not relevant_line.done and item_category == "ingredients" then button_color = "cyan" end
            first_special_index = first_special_index or index
        else
            -- items/s/machine does not make sense for lines with subfloors, show items/s instead
            local machine_amount = (line.class == "Line") and line.machine.amount or nil
            amount, number_tooltip = item_views.process_item(metadata.player, proto, item.amount, machine_amount)
            if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error

            if type == "entity" then
                button_color = (relevant_line.done) and "disabled_grayscale" or "disabled"
            else
                tags.on_gui_click = "act_on_compact_item"
                action_line = {"", "\n", metadata.action_tooltips["act_on_compact_item"]}

                if type == "fluid" and item_category == "ingredients" and line.class ~= "Floor" then
                    local temperature_data = line.recipe.temperature_data[proto.name]
                    table.insert(name_line, temperature_data.annotation)

                    local temperature = line.recipe:get_temperature(proto)
                    if temperature == nil then
                        button_color = "purple"
                        temperature_line = {"fp.no_temperature_configured"}
                    else
                        temperature_line = {"fp.configured_temperature", temperature}
                    end
                end
            end
        end

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, temperature_line, number_line, action_line}
        local style = "fflib_slot_button_" .. button_color .. "_small"

        local button = item_table.add{type="sprite-button", tags=tags, sprite=proto.sprite, number=amount,
            style=style, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        local name = (line.class == "Line") and line.recipe:get_name_with_temperature(proto) or proto.name
        item_buttons[type] = item_buttons[type] or {}
        item_buttons[type][name] = item_buttons[type][name] or {}
        table.insert(item_buttons[type][name], {button=button, proper_style=style, size="_small"})

        ::skip_item::
    end

    if line.class == "Floor" then return end
    ---@cast line Line

    if item_category == "products" or item_category == "ingredients" then
        local recipe_proto = line.recipe--[[@cast -nil]].proto  ---@as FPRecipePrototype
        for _, item in pairs(recipe_proto.catalysts[item_category]) do
            local item_proto = prototyper.util.find("items", item.name, item.type)  ---@as FPItemPrototype

            local amount, number_tooltip = item_views.process_item(metadata.player, item_proto,
                (item.amount * line.production_ratio), line.machine.amount)
            local title_line = {"fp.tt_title_with_note", item_proto.localised_name, {"fp.catalyst"}}
            local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""

            item_table.add{type="sprite-button", sprite=item_proto.sprite, number=amount,
                tooltip={"", title_line, number_line}, style="fflib_slot_button_blue_small"}
        end
    end

    if item_category == "ingredients" and line.machine.fuel then
        local fuel = line.machine.fuel
        local amount, number_tooltip = item_views.process_item(metadata.player, fuel.proto--[[@as FPFuelPrototype]],
            fuel.amount, line.machine.amount)
        if amount == -1 then goto skip_fuel end  -- an amount of -1 means it was below the margin of error

        local style = "fflib_slot_button_cyan_small"
        local name_line = {"fp.tt_title_with_note", fuel.proto.localised_name, {"fp.pu_fuel", 1}}
        local temperature_line = ""  ---@type LocalisedString

        if fuel.proto.type == "fluid" then
            local temperature_data = fuel.temperature_data   -- exists for any fluid fuel
            table.insert(name_line, temperature_data.annotation)

            if fuel.temperature == nil then
                style = "fflib_slot_button_purple_small"
                temperature_line = {"fp.no_temperature_configured"}
            else
                temperature_line = {"fp.configured_temperature", fuel.temperature}
            end
        end

        style = (relevant_line.done) and "fflib_slot_button_grayscale_small" or style
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, temperature_line, number_line, "\n",
            metadata.action_tooltips["act_on_compact_item"]}

        ---@class ActOnCompactFuelTags
        ---@field fuel_id ObjectID
        ---@field context "compact_dialog"
        local tags = {mod="fp", on_gui_click="act_on_compact_item", fuel_id=fuel.id, on_gui_hover="hover_compact_item",
            on_gui_leave="leave_compact_item", context="compact_dialog"}

        local button = item_table.add{type="sprite-button", tags=tags, sprite=fuel.proto.sprite, style=style,
            number=amount, mouse_button_filter={"left-and-right"}, raise_hover_events=true, index=first_special_index}
        metadata.tooltips[button.index] = tooltip

        local type, name = fuel.proto.type, fuel:get_name_with_temperature()
        item_buttons[type] = item_buttons[type] or {}
        item_buttons[type][name] = item_buttons[type][name] or {}
        table.insert(item_buttons[type][name], {button=button, proper_style=style, size="_small"})

        ::skip_fuel::
    end
end


---@param player LuaPlayer
---@param factory Factory
local function refresh_compact_header(player, factory)
    local player_table = lib.globals.player_table(player)
    local compact_elements = player_table.ui_state.compact_elements

    local attach_factory_products = player_table.preferences.attach_factory_products
    compact_elements.name_label.caption = factory:tostring(attach_factory_products, true)

    local current_floor = lib.context.get(player, "Floor")  ---@as Floor
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
    local column_count = math.max(math.floor(available_space / 40), 1)
    local padding = (available_space - (column_count * 40)) / 2
    ingredients_frame.style.padding = {0, padding}

    local item_frame = ingredients_frame.add{type="frame", style="slot_button_deep_frame"}
    local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}

    local item_buttons = compact_elements.item_buttons
    local show_floor_items = player_table.preferences.show_floor_items
    local relevant_floor = (show_floor_items) and current_floor or factory.top_floor
    local action_tooltip = MODIFIER_ACTIONS["act_on_compact_ingredient"].tooltip

    for index, ingredient in pairs(relevant_floor.ingredients) do
        local amount, number_tooltip = nil, nil
        local action_line = ""  ---@type LocalisedString

        ---@class ActOnCompactIngredientTags
        ---@field floor_id ObjectID
        ---@field item_index integer
        ---@field context "compact_dialog"
        local tags = {mod="fp", floor_id=relevant_floor.id, item_index=index, on_gui_hover="hover_compact_item",
            on_gui_leave="leave_compact_item", context="compact_dialog"}

        if ingredient.proto.type == "entity" and ingredient.proto.special then
            amount = lib.format.button_number(ingredient.amount)
            number_tooltip = lib.format.special_tooltip(ingredient.proto.name, ingredient.amount)
        else
            amount, number_tooltip = item_views.process_item(player, ingredient.proto, ingredient.amount, nil)
            if amount == -1 then goto skip_ingredient end  -- an amount of -1 means it was below the margin of error

            tags.on_gui_click = "act_on_compact_ingredient"
            action_line = {"", "\n", action_tooltip}
        end

        local style = "fflib_slot_button_default"
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""  ---@type LocalisedString
        local tooltip = {"", {"fp.tt_title", ingredient.proto.localised_name}, number_line, action_line}

        local button = table_items.add{type="sprite-button", tags=tags, number=amount, tooltip=tooltip,
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

---@param player LuaPlayer
---@param factory Factory
local function refresh_compact_production(player, factory)
    local ui_state = lib.globals.ui_state(player)
    local compact_elements = ui_state.compact_elements

    local floor = lib.context.get(player, "Floor")  ---@as Floor

    local production_table = compact_elements.production_table
    production_table.clear()

    -- Available columns for items only, as recipe and machines can't be 'compressed'
    local frame_width = compact_elements.compact_frame.style.maximal_width
    local available_columns = determine_available_columns(floor, frame_width)
    if available_columns < 2 then available_columns = 2 end  -- fix for too many modules or too high of a GUI scale
    local column_counts = determine_column_counts(floor, available_columns)

    ---@class CompactMetadata
    ---@field player LuaPlayer
    ---@field parent LuaGuiElement
    ---@field column_counts CompactColumnCounts
    ---@field tooltips table
    ---@field action_tooltips table
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
        local relevant_line = (line.class == "Floor") and line.first or line  ---@as Line
        if not relevant_line.active or not relevant_line:get_surface_compatibility().overall
                or (not factory.matrix_solver_active and relevant_line.recipe.production_type == "consume") then
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
        add_item_flow(line, relevant_line, "products", "default", metadata, compact_elements.item_buttons)
        add_item_flow(line, relevant_line, "byproducts", "red", metadata, compact_elements.item_buttons)
        add_item_flow(line, relevant_line, "ingredients", "green", metadata, compact_elements.item_buttons)

        production_table.add{type="empty-widget", style="fflib_horizontal_pusher"}

        ::skip_line::
    end
end

---@param player LuaPlayer
local function refresh_compact_factory(player)
    local factory = lib.context.get(player, "Factory")  ---@as Factory?
    if not factory or not factory.valid then return end

    local ui_state = lib.globals.ui_state(player)
    ui_state.tooltips.compact_dialog = {}
    ui_state.compact_elements.item_buttons = {}

    refresh_compact_header(player, factory)
    refresh_compact_production(player, factory)
end

---@param player LuaPlayer
local function build_compact_factory(player)
    local ui_state = lib.globals.ui_state(player)
    local compact_elements = ui_state.compact_elements
    local content_flow = compact_elements.content_flow

    -- Header frame
    local subheader = content_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    subheader.style.padding = 4

    -- View state
    local container_views = subheader.add{type="flow", direction="horizontal"}
    container_views.style.padding = {4, 4, 0, 0}
    container_views.add{type="empty-widget", style="fflib_horizontal_pusher"}

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

    ---@class ChangeCompactFloorTags
    ---@field destination FloorDestination
    local up_tags = {mod="fp", on_gui_click="change_compact_floor", destination="up"}
    local button_floor_up = flow_navigation.add{type="sprite-button", tags=up_tags, sprite="fp_arrow_line_up",
        tooltip={"fp.floor_up_tt"}, style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    compact_elements["floor_up_button"] = button_floor_up

    local top_tags = {mod="fp", on_gui_click="change_compact_floor", destination="top"}  ---@type ChangeCompactFloorTags
    local button_floor_top = flow_navigation.add{type="sprite-button", tags=top_tags, sprite="fp_arrow_line_bar_up",
        tooltip={"fp.floor_top_tt"}, style="fp_sprite-button_rounded_icon", mouse_button_filter={"left"}}
    button_floor_top.style.padding = {3, 2, 1, 2}
    compact_elements["floor_top_button"] = button_floor_top

    flow_navigation.add{type="empty-widget", style="fflib_horizontal_pusher"}

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
        style="fflib_naked_scroll_pane_no_padding"}
    scroll_pane_production.horizontal_scroll_policy = "never"
    scroll_pane_production.style.horizontally_stretchable = true
    scroll_pane_production.style.extra_right_padding_when_activated = -8

    local table_production = scroll_pane_production.add{type="table", column_count=6, style="fp_table_production"}
    table_production.vertical_centering = false
    table_production.style.horizontal_spacing = 12
    table_production.style.vertical_spacing = 8
    table_production.style.padding = {4, 8}
    compact_elements["production_table"] = table_production

    refresh_compact_factory(player)
end

---@param player any
---@param destination FloorDestination
local function change_floor(player, destination)
    if lib.context.ascend_floors(player, destination) then
        refresh_compact_factory(player)
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactIngredientTags
---@param action string
local function handle_ingredient_click(player, tags, action)
    local floor = OBJECT_INDEX[tags.floor_id]  ---@as Floor
    local item = floor.ingredients[tags.item_index]  ---@as SimpleItem

    if action == "put_into_cursor" then
        lib.cursor.handle_item_click(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        local name = (item.proto.temperature) and item.proto.base_name or item.proto.name
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactRecipeTags
---@param action string
local function handle_recipe_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as LineObject
    local relevant_line = (line.class == "Floor") and line.first or line

    if action == "open_subfloor" then
        if line.class == "Floor" then
            lib.context.set(player, line--[[@as Floor]])
            refresh_compact_factory(player)
        end
    elseif action == "factoriopedia" then
        local proto = relevant_line--[[@as Line]].recipe.proto  ---@as FPRecipePrototype
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto("recipe", proto.name, proto))
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactModuleTags
---@param action string
local function handle_module_click(player, tags, action)
    local module = OBJECT_INDEX[tags.module_id]  ---@as Module

    if action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["item"][module.proto.name])
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactMachineTags
---@param action string
local function handle_machine_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line
    -- We don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        lib.cursor.set_entity(player, line, line.machine)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["entity"][line.machine.proto.name])
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactBeaconTags
---@param action string
local function handle_beacon_click(player, tags, action)
    local line = OBJECT_INDEX[tags.line_id]  ---@as Line
    ---@cast line.beacon -nil
    -- We don't need to care about relevant lines here because this only gets called on lines without subfloor

    if action == "put_into_cursor" then
        lib.cursor.set_entity(player, line, line.beacon)

    elseif action == "factoriopedia" then
        player.open_factoriopedia_gui(prototypes["entity"][line.beacon.proto.name])
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactItemTags | ActOnCompactFuelTags
---@param action string
local function handle_item_click(player, tags, action)
    local item  ---@type SimpleItem | Fuel
    if tags.fuel_id then  ---@cast tags ActOnCompactFuelTags
        item = OBJECT_INDEX[tags.fuel_id]  ---@as Fuel
        ---@cast item.proto FPFuelPrototype
    else  ---@cast tags ActOnCompactItemTags
        item = OBJECT_INDEX[tags.line_id][tags.item_category][tags.item_index]
        ---@cast item.proto FPItemPrototype
    end

    if action == "put_into_cursor" then
        if item.proto.type == "entity" then return end
        lib.cursor.handle_item_click(player, item.proto, item.amount)

    elseif action == "factoriopedia" then
        local name = item.proto.name
        if item.proto.type == "entity" then name = name:gsub("custom%-", "")
        elseif item.proto.temperature then name = item.proto.base_name--[[@as string]] end
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end

---@param player LuaPlayer
---@param tags ActOnCompactIngredientTags | ActOnCompactItemTags | ActOnCompactFuelTags
---@param event EventData.on_gui_hover | EventData.on_gui_leave
local function handle_hover_change(player, tags, event)
    local type, name = nil, nil
    if tags.floor_id then  ---@cast tags ActOnCompactIngredientTags
        local floor = OBJECT_INDEX[tags.floor_id]  ---@as Floor
        local proto = floor.ingredients[tags.item_index]--[[@cast -nil]].proto
        type, name = proto.type, proto.name
    elseif tags.fuel_id then  ---@cast tags ActOnCompactFuelTags
        local fuel = OBJECT_INDEX[tags.fuel_id]  ---@type Fuel
        type, name = fuel.proto.type, fuel:get_name_with_temperature()
    else  ---@cast tags ActOnCompactItemTags
        local line = OBJECT_INDEX[tags.line_id]  ---@type Line
        local proto = line[tags.item_category][tags.item_index]--[[@cast -nil]].proto
        if line.class == "Line" and tags.item_category == "ingredients" then
            type, name = proto.type, line.recipe:get_name_with_temperature(proto)
        else
            type, name = proto.type, proto.name
        end
    end

    local compact_elements = lib.globals.ui_state(player).compact_elements
    local relevant_buttons = compact_elements.item_buttons[type][name]
    for _, button_data in pairs(relevant_buttons) do
        button_data.button.style = (event.name == defines.events.on_gui_hover)
            and "fflib_slot_button_pink" .. button_data.size or button_data.proper_style
    end
end


-- ** EVENTS **
local factory_listeners = {}  ---@type ListenerDefinitions

factory_listeners.gui = {
    on_gui_click = {
        {
            name = "change_compact_floor",
            handler = function(player, tags, _)
                ---@cast tags ChangeCompactFloorTags
                change_floor(player, tags.destination)
            end
        },
        {
            name = "toggle_compact_ingredients",
            handler = function(player, _, _)
                local preferences = lib.globals.preferences(player)
                preferences.compact_ingredients = not preferences.compact_ingredients

                local compact_elements = lib.globals.ui_state(player).compact_elements
                local sprite = (preferences.compact_ingredients) and "fp_dropup" or "utility/dropdown"
                compact_elements.ingredient_toggle.sprite = sprite
                compact_elements.ingredients_frame.visible = preferences.compact_ingredients
            end
        },
        {
            name = "act_on_compact_ingredient",
            actions_table = {
                put_into_cursor = {shortcut="left", show=true},
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
                put_into_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_machine_click
        },
        {
            name = "act_on_compact_beacon",
            actions_table = {
                put_into_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_beacon_click
        },
        {
            name = "act_on_compact_item",
            actions_table = {
                put_into_cursor = {shortcut="left", show=true},
                factoriopedia = {shortcut="alt-right", show=true}
            },
            handler = handle_item_click
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "checkmark_compact_line",
            handler = function(player, tags, _)
                ---@cast tags CheckmarkCompactLineTags
                local line = OBJECT_INDEX[tags.line_id]  ---@as LineObject
                local relevant_line = (line.class == "Floor") and line.first or line
                relevant_line.done = not relevant_line.done
                refresh_compact_factory(player)
            end
        }
    },
    on_gui_hover = {
        {
            name = "hover_compact_item",
            handler = function(player, tags, event)
                ---@cast tags ActOnCompactIngredientTags | ActOnCompactItemTags | ActOnCompactFuelTags
                ---@cast event EventData.on_gui_hover
                handle_hover_change(player, tags, event)
                main_dialog.set_tooltip(player, event.element)
            end
        }
    },
    on_gui_leave = {
        {
            name = "leave_compact_item",
            handler = handle_hover_change
        }
    }
}  ---@as GUIListenerDefinition

factory_listeners.player = {
    fp_up_floor = function(player, _)
        if compact_dialog.is_in_focus(player) then change_floor(player, "up") end
    end,
    fp_top_floor = function(player, _)
        if compact_dialog.is_in_focus(player) then change_floor(player, "top") end
    end,

    build_gui_element = function(player, event)
        ---@cast event BuildGUIElementEventData
        if event.trigger == "compact_factory" then
            build_compact_factory(player)
        end
    end,
    refresh_gui_element = function(player, event)
        ---@cast event RefreshGUIElementEventData
        if event.trigger == "compact_factory" then
            refresh_compact_factory(player)
        end
    end
}


-- ** UTIL **
-- Set frame dimensions in a relative way, taking player resolution and scaling into account
---@param player LuaPlayer
---@param frame LuaGuiElement
local function set_compact_frame_dimensions(player, frame)
    local scaled_resolution = lib.gui.calculate_scaled_resolution(player)
    local compact_width_percentage = lib.globals.preferences(player).compact_width_percentage
    frame.style.width = scaled_resolution.width * (compact_width_percentage / 100)  ---@as integer
    frame.style.maximal_height = scaled_resolution.height * 0.8  ---@as integer
end

---@param player LuaPlayer
---@param frame LuaGuiElement
local function set_compact_frame_location(player, frame)
    local scale = player.display_scale  ---@as integer
    frame.location = {x = 10 * scale, y = 63 * scale}
end


-- ** TOP LEVEL **
compact_dialog = {}

---@param player LuaPlayer
---@param default_visibility boolean
---@return LuaGuiElement
function compact_dialog.rebuild(player, default_visibility)
    local ui_state = lib.globals.ui_state(player)

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

    flow_title_bar.add{type="empty-widget", style="fflib_titlebar_drag_handle",
        ignored_by_interaction=true}
    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="fp_label_frame_title",
        ignored_by_interaction=true}
    flow_title_bar.add{type="empty-widget", style="fflib_titlebar_drag_handle",
        ignored_by_interaction=true}

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="close_compact_dialog"},
        sprite="utility/close", tooltip={"fp.close_interface"}, style="fp_button_frame", mouse_button_filter={"left"}}
    button_close.style.padding = 1

    local flow_content = frame_compact_dialog.add{type="flow", direction="vertical"}
    flow_content.style.vertical_spacing = 8
    ui_state.compact_elements["content_flow"] = flow_content

    item_views.rebuild_data(player)
    lib.gui.run_build(player, "compact_factory", nil)  -- tells all elements to build themselves
    item_views.rebuild_interface(player)

    return frame_compact_dialog
end

---@param player LuaPlayer
function compact_dialog.toggle(player)
    local frame_compact_dialog = lib.globals.ui_state(player).compact_elements.compact_frame
    -- Doesn't set player.opened so other GUIs like the inventory can be opened when building

    if frame_compact_dialog == nil or not frame_compact_dialog.valid then
        compact_dialog.rebuild(player, true)  -- refreshes on its own
    else
        local new_dialog_visibility = not frame_compact_dialog.visible
        frame_compact_dialog.visible = new_dialog_visibility

        if new_dialog_visibility then refresh_compact_factory(player) end
    end
end

---@param player LuaPlayer
---@return boolean
function compact_dialog.is_in_focus(player)
    local frame_compact_dialog = lib.globals.ui_state(player).compact_elements.compact_frame
    return (frame_compact_dialog ~= nil and frame_compact_dialog.valid and frame_compact_dialog.visible)
end


-- ** EVENTS **
local dialog_listeners = {}  ---@type ListenerDefinitions

dialog_listeners.gui = {
    on_gui_click = {
        {
            name = "switch_to_main_view",
            handler = function(player, _, _)
                lib.globals.ui_state(player).compact_view = false
                compact_dialog.toggle(player)

                main_dialog.toggle(player)
                lib.gui.run_refresh(player, "production")
            end
        },
        {
            name = "close_compact_dialog",
            handler = function(player, _, _)
                compact_dialog.toggle(player)
            end
        },
        {
            name = "place_compact_dialog",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_click
                if event.button == defines.mouse_button_type.middle then
                    local frame_compact_dialog = lib.globals.ui_state(player).compact_elements.compact_frame
                    set_compact_frame_location(player, frame_compact_dialog)
                end
            end
        }
    }
}  ---@as GUIListenerDefinition

dialog_listeners.player = {
    on_player_display_resolution_changed = function(player, _)
        compact_dialog.rebuild(player, false)
    end,

    on_player_display_scale_changed = function(player, _)
        compact_dialog.rebuild(player, false)
    end,

    on_lua_shortcut = function(player, event)
        ---@cast event EventData.on_lua_shortcut
        if event.prototype_name == "fp_open_interface" and lib.globals.ui_state(player).compact_view then
            compact_dialog.toggle(player)
        end
    end,

    fp_toggle_interface = function(player, _)
        if lib.globals.ui_state(player).compact_view then compact_dialog.toggle(player) end
    end
}

return { factory_listeners, dialog_listeners }

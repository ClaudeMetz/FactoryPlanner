ui_util = {
    context = {},
    clipboard = {},
    messages = {},
    switch = {}
}

-- Properly centers the given frame (need width/height parameters cause no API-read exists)
---@param player LuaPlayer
---@param frame LuaGuiElement
---@param dimensions DisplayResolution
function ui_util.properly_center_frame(player, frame, dimensions)
    local resolution, scale = player.display_resolution, player.display_scale
    local x_offset = ((resolution.width - (dimensions.width * scale)) / 2)
    local y_offset = ((resolution.height - (dimensions.height * scale)) / 2)
    frame.location = {x_offset, y_offset}
end

---@param textfield LuaGuiElement
function ui_util.setup_textfield(textfield)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
end

---@param textfield LuaGuiElement
---@param decimal boolean
---@param negative boolean
function ui_util.setup_numeric_textfield(textfield, decimal, negative)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
    textfield.numeric = true
    textfield.allow_decimal = (decimal or false)
    textfield.allow_negative = (negative or false)
end

---@param textfield LuaGuiElement
function ui_util.select_all(textfield)
    textfield.focus()
    textfield.select_all()
end


---@param player LuaPlayer
---@param text LocalisedString
function ui_util.create_flying_text(player, text)
    player.create_local_flying_text{text=text, create_at_cursor=true}
end

---@param player LuaPlayer
---@param blueprint_entities BlueprintEntity[]
function ui_util.create_cursor_blueprint(player, blueprint_entities)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="fp_cursor_blueprint"}
    blank_slot.set_blueprint_entities(blueprint_entities)
    player.add_to_clipboard(blank_slot)
    player.activate_paste()
    script_inventory.destroy()
end

---@param player LuaPlayer
---@param line FPLine
---@param object FPMachine | FPBeacon
---@return boolean success
function ui_util.put_entity_into_cursor(player, line, object)
    local entity_prototype = game.entity_prototypes[object.proto.name]
    if entity_prototype.has_flag("not-blueprintable") or not entity_prototype.has_flag("player-creation")
            or entity_prototype.items_to_place_this == nil then
        ui_util.create_flying_text(player, {"fp.put_into_cursor_failed", entity_prototype.localised_name})
        return false
    end

    local module_list = {}
    for _, module in pairs(ModuleSet.get_in_order(object.module_set)) do
        module_list[module.proto.name] = module.amount
    end

    local blueprint_entity = {
        entity_number = 1,
        name = object.proto.name,
        position = {0, 0},
        items = module_list,
        recipe = (object.class == "Machine") and line.recipe.proto.name or nil
    }

    ui_util.create_cursor_blueprint(player, {blueprint_entity})
    return true
end

---@param player LuaPlayer
---@param items { [string]: number }
---@return boolean success
function ui_util.put_item_combinator_into_cursor(player, items)
    local combinator_proto = game.entity_prototypes["constant-combinator"]
    if combinator_proto == nil then
        ui_util.create_flying_text(player, {"fp.blueprint_no_combinator_prototype"})
        return false
    elseif not next(items) then
        ui_util.create_flying_text(player, {"fp.impossible_to_blueprint_fluid"})
        return false
    end
    local filter_limit = combinator_proto.item_slot_count

    local blueprint_entities = {}  ---@type BlueprintEntity[]
    local current_combinator, current_filter_count = nil, 0
    local next_entity_number, next_position = 1, {0, 0}

    for proto_name, item_amount in pairs(items) do
        if not current_combinator or current_filter_count == filter_limit then
            current_combinator = {
                entity_number = next_entity_number,
                name = "constant-combinator",
                tags = {fp_item_combinator = true},
                position = next_position,
                control_behavior = {filters = {}},
                connections = {{green = {}}}  -- filled in below
            }
            table.insert(blueprint_entities, current_combinator)

            next_entity_number = next_entity_number + 1
            next_position = {next_position[1] + 1, 0}
            current_filter_count = 0
        end

        current_filter_count = current_filter_count + 1
        table.insert(current_combinator.control_behavior.filters, {
            signal = {type = 'item', name = proto_name},
            count = math.max(item_amount, 1),  -- make sure amounts < 1 are not excluded
            index = current_filter_count
        })
    end

    ---@param main_entity BlueprintEntity
    ---@param other_entity BlueprintEntity
    local function connect_if_entity_exists(main_entity, other_entity)
        if other_entity ~= nil then
            local entry = {entity_id = other_entity.entity_number}
            table.insert(main_entity.connections[1].green, entry)
        end
    end

    for index, entity in ipairs(blueprint_entities) do
        connect_if_entity_exists(entity, blueprint_entities[index-1])
        if not next(entity.connections[1].green) then entity.connections = nil end
    end

    ui_util.create_cursor_blueprint(player, blueprint_entities)
    return true
end

---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param amount number
function ui_util.add_item_to_cursor_combinator(player, proto, amount)
    if proto.type ~= "item" then
        ui_util.create_flying_text(player, {"fp.impossible_to_blueprint_fluid"})
        return
    end

    local items = {}
    local blueprint_entities = player.get_blueprint_entities()
    if blueprint_entities ~= nil then
        for _, entity in pairs(blueprint_entities) do
            if entity.tags ~= nil and entity.tags["fp_item_combinator"] then
                for _, filter in pairs(entity.control_behavior.filters) do
                    items[filter.signal.name] = filter.count
                end
            end
        end
    end

    items[proto.name] = (items[proto.name] or 0) + amount
    ui_util.put_item_combinator_into_cursor(player, items)  -- don't care about success here
end


-- This function is only called when Recipe Book is active, so no need to check for the mod
---@param player LuaPlayer
---@param type string
---@param name string
function ui_util.open_in_recipebook(player, type, name)
    local message = nil

    if remote.call("RecipeBook", "version") ~= RECIPEBOOK_API_VERSION then
        message = {"fp.error_recipebook_version_incompatible"}
    else
        local was_opened = remote.call("RecipeBook", "open_page", player.index, type, name)
        if not was_opened then message = {"fp.error_recipebook_lookup_failed", {"fp.pl_" .. type, 1}} end
    end

    if message then util.messages.raise(player, "error", message, 1) end
end

-- Destroys all GUIs so they are loaded anew the next time they are shown
---@param player LuaPlayer
function ui_util.reset_player_gui(player)
    util.mod_gui.destroy(player)  -- mod_gui button

    for _, gui_element in pairs(player.gui.screen.children) do  -- all mod frames
        if gui_element.valid and gui_element.get_mod() == "factoryplanner" then
            gui_element.destroy()
        end
    end
end


-- Formats given number to given number of significant digits
---@param number number
---@param precision integer
---@return string formatted_number
function ui_util.format_number(number, precision)
    -- To avoid scientific notation, chop off the decimals points for big numbers
    if (number / (10 ^ precision)) >= 1 then
        return ("%d"):format(number)
    else
        -- Set very small numbers to 0
        if number < (0.1 ^ precision) then
            number = 0

        -- Decrease significant digits for every zero after the decimal point
        -- This keeps the number of digits after the decimal point constant
        elseif number < 1 then
            local n = number
            while n < 1 do
                precision = precision - 1
                n = n * 10
            end
        end

        -- Show the number in the shortest possible way
        return ("%." .. precision .. "g"):format(number)
    end
end

-- Returns string representing the given power
---@param value number
---@param unit string
---@param precision integer
---@return LocalisedString formatted_number
function ui_util.format_SI_value(value, unit, precision)
    local prefixes = {"", "kilo", "mega", "giga", "tera", "peta", "exa", "zetta", "yotta"}
    local units = {
        ["W"] = {"fp.unit_watt"},
        ["J"] = {"fp.unit_joule"},
        ["P/m"] = {"", {"fp.unit_pollution"}, "/", {"fp.unit_minute"}}
    }

    local sign = (value >= 0) and "" or "-"
    value = math.abs(value) or 0

    local scale_counter = 0
    -- Determine unit of the energy consumption, while keeping the result above 1 (ie no 0.1kW, but 100W)
    while scale_counter < #prefixes and value > (1000 ^ (scale_counter + 1)) do
        scale_counter = scale_counter + 1
    end

    -- Round up if energy consumption is close to the next tier
    if (value / (1000 ^ scale_counter)) > 999 then
        scale_counter = scale_counter + 1
    end

    value = value / (1000 ^ scale_counter)
    local prefix = (scale_counter == 0) and "" or {"fp.prefix_" .. prefixes[scale_counter + 1]}
    return {"", sign .. ui_util.format_number(value, precision) .. " ", prefix, units[unit]}
end


---@param count number
---@param active boolean
---@param round_number boolean
---@return string formatted_count
---@return LocalisedString tooltip_line
function ui_util.format_machine_count(count, active, round_number)
    -- The formatting is used to 'round down' when the decimal is very small
    local formatted_count = ui_util.format_number(count, 3)
    local tooltip_count = formatted_count

    -- If the formatting returns 0, it is a very small number, so show it as 0.001
    if formatted_count == "0" and active then
        tooltip_count = "≤0.001"
        formatted_count = "0.01"  -- shows up as 0.0 on the button
    end

    if round_number then formatted_count = tostring(math.ceil(formatted_count --[[@as number]])) end

    local plural_parameter = (tooltip_count == "1") and 1 or 2
    local tooltip_line = {"", tooltip_count, " ", {"fp.pl_machine", plural_parameter}}

    return formatted_count, tooltip_line
end

ui_util = {
    message = {},
    fnei = {}
}

-- Readjusts the size of the main dialog according to the user settings
function ui_util.recalculate_main_dialog_dimensions(player)
    local player_table = get_table(player)

    local width = 880 + ((player_table.settings.items_per_row - 4) * 175)
    local height = 395 + (player_table.settings.recipes_at_once * 39)

    local dimensions = {width=width, height=height}
    player_table.ui_state.main_dialog_dimensions = dimensions
    return dimensions
end

-- Properly centers the given frame (need width/height parameters cause no API-read exists)
function ui_util.properly_center_frame(player, frame, width, height)
    local resolution = player.display_resolution
    local scale = player.display_scale
    local x_offset = ((resolution.width - (width * scale)) / 2) 
    local y_offset = ((resolution.height - (height * scale)) / 2)
    frame.location = {x_offset, y_offset}
end


-- Checks whether the archive is open; posts an error and returns true if it is
function ui_util.check_archive_status(player, mute)
    if get_ui_state(player).archive_open then
        if not mute then 
            ui_util.message.enqueue(player, {"label.error_editing_archived_subfactory"}, "error", 1)
        end
        return true
    else
        return false
    end
end


-- Sets the font color of the given label / button-label
function ui_util.set_label_color(ui_element, color)
    if color == nil then
        return
    elseif color == "red" then
        ui_element.style.font_color = {r = 1, g = 0.2, b = 0.2}
    elseif color == "dark_red" then
        ui_element.style.font_color = {r = 0.8, g = 0, b = 0}
    elseif color == "yellow" then
        ui_element.style.font_color = {r = 0.8, g = 0.8, b = 0}
    elseif color == "green" then
        ui_element.style.font_color = {r = 0.2, g = 0.8, b = 0.2}
    elseif color == "white" or color == "default_label" then
        ui_element.style.font_color = {r = 1, g = 1, b = 1}
    elseif color == "black" or color == "default_button" then
        ui_element.style.font_color = {r = 0, g = 0, b = 0}
    end
end

 
-- Adds the appropriate tutorial tooltip if the preference is enabled
function ui_util.add_tutorial_tooltip(button, type, line_break, fnei)
    local player = game.get_player(button.player_index)
    if get_preferences(player).tutorial_mode then
        local b = line_break and "\n\n" or ""
        local f = (fnei and remote.interfaces["fnei"] ~= nil) and {"tip.tut_fnei"} or ""
        button.tooltip = {"", button.tooltip, b, {"tooltip.tut_mode"}, "\n", {"tip.tut_" .. type}, f}
    end
end


-- Sets basic attributes on the given textfield
function ui_util.setup_textfield(textfield)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
end

-- Sets up the given textfield as a numeric one, with the specified options
function ui_util.setup_numeric_textfield(textfield, decimal, negative)
    ui_util.setup_textfield(textfield)
    textfield.numeric = true
    textfield.allow_decimal = (decimal or false)
    textfield.allow_negative = (negative or false)
end


-- Returns the number to put on an item button according to the current view
function ui_util.calculate_item_button_number(player_table, view, amount, type, machine_count)
    local timescale = player_table.ui_state.context.subfactory.timescale
    
    local number = nil
    if view.name == "items_per_timescale" then
        number = amount
    elseif view.name == "belts_or_lanes" and type ~= "fluid" then
        local throughput = player_table.preferences.preferred_belt.throughput
        local divisor = (player_table.settings.belts_or_lanes == "belts") and throughput or (throughput / 2)
        number = amount / divisor / timescale
    elseif view.name == "items_per_second_per_machine" and type ~= "fluid" then
        -- Show items/s/1 (machine) if it's a top level item, or machine_count is at 0
        machine_count = (machine_count ~= nil and machine_count ~= 0) and machine_count or 1
        number = amount / timescale / machine_count
    end

    return number  -- number might be nil here
end


-- Adds an appropriate number and tooltip to the given button using the given item/top-level-item
-- (Relates to the view_state, doesn't do anything if views are uninitialised)
function ui_util.setup_item_button(player_table, button, item, line)
    local view_state = player_table.ui_state.view_state
    -- This gets refreshed after the view state is initialised
    if view_state == nil then return end

    local view = view_state[view_state.selected_view_id]
    local amount = (item.top_level and item.class == "Product") and item.required_amount or item.amount
    local machine_count = (line ~= nil) and line.machine.count or nil
    local number = ui_util.calculate_item_button_number(player_table, view, amount, item.proto.type, machine_count)
    
    -- Special handling for mining recipes concerning their localised name
    local localised_name = (item.proto.type == "entity") and {"", {"label.raw"}, " ", item.proto.localised_name}
      or item.proto.localised_name
    
    -- Determine caption
    local function determine_type_text()
        if item.proto.type == "fluid" then
            return {"tooltip.fluid"}
        else
            return ((number == 1) and {"tooltip.item"} or {"tooltip.items"})
        end
    end
    
    local caption = nil
    -- Determine caption appendage
    if view.name == "items_per_timescale" then
        local timescale = player_table.ui_state.context.subfactory.timescale
        caption = {"", determine_type_text(), "/", ui_util.format_timescale(timescale, true, false)}

    elseif view.name == "belts_or_lanes" and item.proto.type ~= "fluid" then
        local belts = (player_table.settings.belts_or_lanes == "belts")
        if belts then
            caption = (number == 1) and {"tooltip.belt"} or {"tooltip.belts"}
        else
            caption = (number == 1) and {"tooltip.lane"} or {"tooltip.lanes"}
        end

    elseif view.name == "items_per_second_per_machine" and item.proto.type ~= "fluid" then
        -- Only show "/machine" if it's not a top level item, where it'll just show items/s
        local s_machine = (machine_count ~= nil) and {"", "/", {"tooltip.machine"}} or ""
        caption = {"", determine_type_text(), "/s", s_machine}

    end

    -- Compose tooltip, respecting top level products
    if number ~= nil then
        number = ui_util.format_number(number, 4)
        
        local number_string
        if item.top_level and item.class == "Product" then
            local formatted_amount = ui_util.calculate_item_button_number(player_table, view, item.amount,
              item.proto.type, nil)
            number_string = {"", ui_util.format_number(formatted_amount, 4), " / ", number}
        else
            number_string = {"", number}
        end

        button.number = (view.name == "belts_or_lanes" and player_table.settings.round_button_numbers)
          and math.ceil(number) or number
        button.tooltip = {"", localised_name, "\n", number_string, " ", caption}
    else
        button.tooltip = localised_name
    end
end

-- Determines a suitable crafting machine sprite path, according to what is available
function ui_util.find_crafting_machine_sprite()
    -- Try these categories first, one of them should exist
    local categories = {"crafting", "advanced-crafting", "basic-crafting"}
    for _, category_name in ipairs(categories) do
        local category_id = global.all_machines.map[category_name]
        if category_id ~= nil then
            local machines = global.all_machines.categories[category_id].machines
            return machines[table_size(machines)].sprite
        end
    end

    -- If none of the specified categories exist, just pick the top tier machine of the first one
    local machines = global.all_machines.categories[1].machines
    return machines[table_size(machines)].sprite
end


-- Returns a tooltip containing the effects of the given module (works for Module-classes or prototypes)
function ui_util.generate_module_effects_tooltip_proto(module)
    -- First, generate the appropriate effects table
    local effects = {}
    local raw_effects = (module.proto ~= nil) and module.proto.effects or module.effects
    for name, effect in pairs(raw_effects) do
        effects[name] = (module.proto ~= nil) and (effect.bonus * module.amount) or effect.bonus
    end

    -- Then, let the tooltip function generate the actual tooltip
    return ui_util.generate_module_effects_tooltip(effects, nil)
end

-- Generates a tooltip out of the given effects, ignoring those that are 0
function ui_util.generate_module_effects_tooltip(effects, machine_proto, player, subfactory)
    local localised_names = {
        consumption = {"tooltip.module_consumption"},
        speed = {"tooltip.module_speed"},
        productivity = {"tooltip.module_productivity"},
        pollution = {"tooltip.module_pollution"}
    }

    local tooltip = {""}
    for name, effect in pairs(effects) do
        if machine_proto ~= nil and name == "productivity" then
            effect = effect + data_util.determine_mining_productivity(player, subfactory, machine_proto)
        end

        if effect ~= 0 then
            local appendage = ""
            
            -- Handle effect caps and mining productivity if this is a machine-tooltip
            if machine_proto ~= nil then
                -- Consumption, speed and pollution are capped at -80%
                if (name == "consumption" or name == "speed" or name == "pollution") and effect < -0.8 then
                    effect = -0.8
                    appendage = {"", " (", {"tooltip.capped"}, ")"}
                    
                -- Productivity can't go lower than 0
                elseif name == "productivity" then
                    if effect < 0 then
                        effect = 0
                        appendage = {"", " (", {"tooltip.capped"}, ")"}
                    end
                end
            end

            -- Force display of either a '+' or '-'
            local number = ("%+d"):format(math.floor((effect * 100) + 0.5))
            tooltip = {"", tooltip, "\n", localised_names[name], ": ", number, "%", appendage}
        end
    end

    return tooltip
end

-- Returns a tooltip containing the attributes of the given beacon prototype
function ui_util.generate_beacon_attributes_tooltip(beacon)
    return {"", {"tooltip.module_slots"}, ": ", beacon.module_limit, "\n",
              {"tooltip.effectivity"}, ": ", (beacon.effectivity * 100), "%", "\n",
              {"label.energy_consumption"}, ": ", ui_util.format_SI_value(beacon.energy_usage, "W", 3)}
end

-- Returns a tooltip containing the attributes of the given fuel prototype
function ui_util.generate_fuel_attributes_tooltip(fuel)
    return {"", {"tooltip.fuel_value"}, ": ", ui_util.format_SI_value(fuel.fuel_value, "J", 3)}
end

-- Returns a tooltip containing the attributes of the given belt prototype
function ui_util.generate_belt_attributes_tooltip(belt)
    return {"", {"tooltip.throughput"}, ": ", belt.throughput, " ", {"tooltip.item"}, "s/s"}
end

-- Returns a tooltip containing the attributes of the given machine prototype
function ui_util.generate_machine_attributes_tooltip(machine)
    return {"", {"tooltip.crafting_speed"}, ": ", machine.speed, "\n",
             {"label.energy_consumption"}, ": ", ui_util.format_SI_value(machine.energy_usage, "W", 3), "\n",
             {"tooltip.module_slots"}, ": ", machine.module_limit}
end


-- Formats given number to given number of significant digits
function ui_util.format_number(number, precision)
    if number == nil then return nil end
    
    -- To avoid scientific notation, chop off the decimals points for big numbers
    if (number / (10 ^ precision)) > 1 then
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

-- Returns string representing the given timescale (Currently only needs to handle 1 second/minute/hour)
function ui_util.format_timescale(timescale, raw, whole_word)
    local ts = nil
    if timescale == 1 then
        ts = whole_word and {"label.second"} or "s"
    elseif timescale == 60 then
        ts = whole_word and {"label.minute"} or "m"
    elseif timescale == 3600 then
        ts = whole_word and {"label.hour"} or "h"
    end
    if raw then return ts
    else return ("1" .. ts) end
end

-- Returns string representing the given power 
function ui_util.format_SI_value(value, unit, precision)
    local scale = {"", "k", "M", "G", "T", "P", "E", "Z", "Y"}
    
    local scale_counter = 0
    -- Determine unit of the energy consumption, while keeping the result above 1 (ie no 0.1kW, but 100W)
    while scale_counter < #scale and value > (1000 ^ (scale_counter + 1)) do
        scale_counter = scale_counter + 1
    end

    -- Round up if energy consumption is close to the next tier
    if (value / (1000 ^ scale_counter)) > 999 then
        scale_counter = scale_counter + 1
    end

    value = value / (1000 ^ scale_counter)
    return (ui_util.format_number(value, precision) .. " " .. scale[scale_counter + 1] .. unit)
end


-- Splits given string
function ui_util.split(s, separator)
    local r = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
        if tonumber(token) ~= nil then
            token = tonumber(token)
        end
        table.insert(r, token) 
    end
    return r
end


-- **** Messages ****
-- Enqueues the given message into the message queue
-- Possible types are error, warning, hint
function ui_util.message.enqueue(player, message, type, lifetime)
    table.insert(get_ui_state(player).message_queue, {text=message, type=type, lifetime=lifetime})
end

-- Refreshes the current message, taking into account priotities and lifetimes
-- The messages are displayed in enqueued order, displaying higher priorities first
-- The lifetime is decreased for every message on every refresh
-- (The algorithm(s) could be more efficient, but it doesn't matter for the small dataset)
function ui_util.message.refresh(player)
    -- The message types are ordered by priority
    local types = {
        [1] = {name = "error", color = "red"},
        [2] = {name = "warning", color = "yellow"},
        [3] = {name = "hint", color = "green"}
    }
    
    local ui_state = get_ui_state(player)
    
    -- Go over the all types and messages, trying to find one that should be shown
    local new_message, new_color = "", nil
    for _, type in ipairs(types) do
        -- All messages will have lifetime > 0 at this point
        for _, message in ipairs(ui_state.message_queue) do
            -- Find first message of this type, then break
            if message.type == type.name then
                new_message = message.text
                new_color = type.color
                break
            end
        end
        -- If a message is found, break because no messages of lower ranked type should be considered
        if new_message ~= "" then break end
    end
    
    -- Decrease the lifetime of every queued message
    for index, message in ipairs(ui_state.message_queue) do
        message.lifetime = message.lifetime - 1
        if message.lifetime <= 0 then table.remove(ui_state.message_queue, index) end
    end
    
    local label_hint = player.gui.screen["fp_frame_main_dialog"]["flow_titlebar"]["label_titlebar_hint"]
    label_hint.caption = new_message
    ui_util.set_label_color(label_hint, new_color)
end


-- **** FNEI ****
-- This indicates the version of the FNEI remote interface this is compatible with
local fnei_version = 2

-- Opens FNEI to show the given item
-- Mirrors FNEI's distinction between left and right clicks
function ui_util.fnei.show_item(item, click)
    if remote.interfaces["fnei"] ~= nil and remote.call("fnei", "version") == fnei_version then
        local action_type = (click == "left") and "craft" or "usage"
        remote.call("fnei", "show_recipe_for_prot", action_type, item.proto.type, item.proto.name)
    end
end

-- Opens FNEI to show the given recipe
function ui_util.fnei.show_recipe(recipe, line_products)
    if remote.interfaces["fnei"] ~= nil and remote.call("fnei", "version") == fnei_version then
        -- Try to determine the relevant product to use as context for the recipe in FNEI
        if recipe.proto.main_product then
            local product = recipe.proto.main_product
            remote.call("fnei", "show_recipe", recipe.proto.name, product.name)
        elseif #line_products == 1 then
            local product = line_products[1]
            remote.call("fnei", "show_recipe", recipe.proto.name, product.proto.name)

        -- If no appropriate context can be determined, FNEI will choose the first ingredient in the list
        else
            remote.call("fnei", "show_recipe", recipe.proto.name)
        end
    end
end
ui_util = {
    message = {},
    fnei = {}
}

-- Readjusts the size of the main dialog according to the user settings
function ui_util.recalculate_main_dialog_dimensions(player)
    local player_table = get_table(player)

    local width = 880 + ((player_table.settings.items_per_row - 4) * 175)
    local height = 395 + (player_table.settings.recipes_at_once * 39)
    player_table.ui_state.main_dialog_dimensions = {width = width, height = height}
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


-- Returns the sprite string of the given item
function ui_util.generate_item_sprite(item)
    return (item.type .. "/" .. item.name)
end

-- Returns the sprite string of the given recipe
function ui_util.generate_recipe_sprite(recipe)
    local sprite = "recipe/" .. recipe.name

    -- Handle custom recipes separately
    if recipe.name == "fp-space-science-pack" then
        sprite = "item/space-science-pack"
    elseif (string.match(recipe.name, "^impostor-.*")) then
        -- If the impostor recipe has exactly one product, use it's sprite
        if #recipe.products == 1 then
            sprite = recipe.products[1].type .. "/" .. recipe.products[1].name
        else  -- Otherwise (0 or 2+ products), use the first ingredient's sprite
            sprite = recipe.ingredients[1].type .. "/" .. recipe.ingredients[1].name
        end
    end

    return sprite
end


-- Returns the number to put on an item button according to the current view
function ui_util.calculate_item_button_number(player_table, view, amount, type)
    local timescale = player_table.ui_state.context.subfactory.timescale
    local number = nil

    if view.name == "items_per_timescale" then
        number = amount
    elseif view.name == "belts_or_lanes" and type ~= "fluid" then
        local throughput = player_table.preferences.preferred_belt.throughput
        local divisor = (player_table.settings.belts_or_lanes == "Belts") and throughput or (throughput / 2)
        number = amount / divisor / timescale
    elseif view.name == "items_per_second" then
        number = amount / timescale
    end

    return number  -- number might be nil here
end


-- Adds an appropriate number and tooltip to the given button using the given item/top-level-item
-- (Relates to the view_state, doesn't do anything if views are uninitialised)
function ui_util.setup_item_button(player_table, button, item)
    local view_state = player_table.ui_state.view_state
    -- This gets refreshed after the view state is initialised
    if view_state == nil then return end

    local view = view_state[view_state.selected_view_id]
    local amount = (item.top_level and item.class == "Product") and item.required_amount or item.amount
    local number = ui_util.calculate_item_button_number(player_table, view, amount, item.proto.type)
    
    -- Special handling for mining recipes concerning their localised name
    local localised_name
    if item.proto.type == "entity" then localised_name = {"", {"label.raw"}, " ", item.proto.localised_name}
    else localised_name = item.proto.localised_name end
    
    -- Determine caption
    local caption
    local function determine_type_text()
        if item.proto.type == "fluid" then
            caption = {"tooltip.fluid"}
        else
            caption = (number == 1) and {"tooltip.item"} or {"", {"tooltip.item"}, "s"}
        end
    end
    
    -- Determine caption appendage
    if view.name == "items_per_timescale" then
        determine_type_text()
        local timescale = player_table.ui_state.context.subfactory.timescale
        caption = {"", caption, "/", ui_util.format_timescale(timescale, true)}

    elseif view.name == "belts_or_lanes" and item.proto.type ~= "fluid" then
        local belts = (player_table.settings.belts_or_lanes == "Belts")
        caption = belts and {"tooltip.belt"} or {"tooltip.lane"}
        if number ~= 1 then caption = {"", caption, "s"} end

    elseif view.name == "items_per_second" then
        determine_type_text()
        caption = {"", caption, "/s"}
    end

    -- Compose tooltip, respecting top level products
    if number ~= nil then
        local number_string
        if item.top_level and item.class == "Product" then
            local formatted_amount = ui_util.calculate_item_button_number(player_table, view, item.amount, item.proto.type)
            number_string = {"", ui_util.format_number(formatted_amount, 4), " / ", ui_util.format_number(number, 4)}
        else
            number_string = {"", ui_util.format_number(number, 4)}
        end

        button.number = ui_util.format_number(number, 4)  --("%.4g"):format(number)
        button.tooltip = {"", localised_name, "\n", number_string, " ", caption}
    else
        button.tooltip = localised_name
    end
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
            -- Handle effect caps and mining productivity if this is a machine-tooltip
            if machine_proto ~= nil then
                local appendage = ""
                -- Consumption is capped at -80%
                if name == "consumption" and effect < -0.8 then
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
              {"tooltip.effectivity"}, ": ", beacon.effectivity, "%"}
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
             {"label.energy_consumption"}, ": ", ui_util.format_SI_value(machine.energy, "W", 3), "\n",
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
function ui_util.format_timescale(timescale, raw)
    local ts = nil
    if timescale == 1 then
        ts = "s"
    elseif timescale == 60 then
        ts = "m"
    elseif timescale == 3600 then
        ts = "h"
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


-- Sorts a table by string-key using an iterator
function ui_util.pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
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
        [1] = {name = "error", color = "red", always_show=true},
        [2] = {name = "warning", color = "yellow", always_show=false},
        [3] = {name = "hint", color = "green", always_show=false}
    }
    
    local ui_state = get_ui_state(player)
    local show_hints = get_settings(player).show_hints
    
    -- Go over the all types and messages, trying to find one that should be shown
    local new_message, new_color = "", nil
    for _, type in ipairs(types) do
        if always_show or show_hints then
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
    end
    
    -- Decrease the lifetime of every queued message
    for index, message in ipairs(ui_state.message_queue) do
        message.lifetime = message.lifetime - 1
        if message.lifetime <= 0 then table.remove(ui_state.message_queue, index) end
    end
    
    local label_hint = player.gui.center["fp_frame_main_dialog"]["flow_titlebar"]["label_titlebar_hint"]
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
ui_util = {
    context = {},
    attributes = {},
    switch = {},
    message = {}
}


-- ** GUI utilities **
-- Readjusts the size of the main dialog according to the user settings
function ui_util.recalculate_main_dialog_dimensions(player)
    local player_table = get_table(player)

    local width = 880 + ((player_table.settings.items_per_row - 4) * 175)
    local height = 394 + (player_table.settings.recipes_at_once * 39)

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

-- Focuses and selects all the text of the given textfield
function ui_util.select_all(textfield)
    textfield.focus()
    textfield.select_all()
end

-- File-local to so this dict isn't recreated on every call of the function following it
local font_colors = {
    red = {r = 1, g = 0.2, b = 0.2},
    dark_red = {r = 0.8, g = 0, b = 0},
    yellow = {r = 0.8, g = 0.8, b = 0},
    green = {r = 0.2, g = 0.8, b = 0.2},
    white = {r = 1, g = 1, b = 1},
    default_label = {r = 1, g = 1, b = 1},
    black = {r = 0, g = 0, b = 0},
    default_button = {r = 0, g = 0, b = 0}
}
-- Sets the font color of the given label / button-label
function ui_util.set_label_color(ui_element, color)
    if color == nil then return
    else ui_element.style.font_color = font_colors[color] end
end

-- Adds the given sprite to the top left corner of the given button
function ui_util.add_overlay_sprite(button, sprite, button_size)
    local overlay = button.add{type="sprite", name="sprite_machine_button_overlay", sprite=sprite}
    overlay.ignored_by_interaction = true
    overlay.resize_to_sprite = false

    -- Set size dynamically according to the button sprite size
    local adjusted_size = math.floor(button_size / 3.2)
    overlay.style.height = adjusted_size
    overlay.style.width = adjusted_size
end


-- ** Tooltips **
-- File-local to so this dict isn't recreated on every call of the function following it
local valid_alt_types = {tl_ingredient=true, tl_product=true, tl_byproduct=true, recipe=true,
  product=true, byproduct=true, ingredient=true, fuel=true}
-- Either adds the tutorial tooltip to the button, or returns it if none is given
function ui_util.tutorial_tooltip(player, button, tut_type, line_break)
    local preferences = get_preferences(player)
    if preferences.tutorial_mode then
        local b = line_break and "\n\n" or ""
        local alt_action = get_settings(player).alt_action
        local f = (valid_alt_types[tut_type] and alt_action ~= "none")
          and {"fp.tut_alt_action", {"fp.alt_action_" .. alt_action}} or ""
        if button ~= nil then
            button.tooltip = {"", button.tooltip, b, {"fp.tut_mode"}, "\n", {"fp.tut_" .. tut_type}, f}
        else
            return {"", b, {"fp.tut_mode"}, "\n", {"fp.tut_" .. tut_type}, f}
        end
    -- Return empty string if there should be a return value
    elseif button == nil then
        return ""
    end
end

-- Determines the raw amount and the text-appendage for the given item (spec. by type, amount)
function ui_util.determine_item_amount_and_appendage(player_table, view_name, item_type, amount, machine_count)
    local timescale = player_table.ui_state.context.subfactory.timescale
    local number, appendage = nil, ""

    if view_name == "items_per_timescale" then
        number = amount

        local type_text = (item_type == "fluid") and {"fp.fluid"} or
          ((number == 1) and {"fp.item"} or {"fp.items"})
        appendage = {"", type_text, "/", ui_util.format_timescale(timescale, true, false)}

    elseif view_name == "belts_or_lanes" and item_type ~= "fluid" then
        local player = game.get_player(player_table.index)
        local throughput = prototyper.defaults.get(player, "belts").throughput
        local show_belts = (player_table.settings.belts_or_lanes == "belts")
        local divisor = (show_belts) and throughput or (throughput / 2)
        number = amount / divisor / timescale

        appendage = (show_belts) and ((number == 1) and {"fp.belt"} or {"fp.belts"}) or
          ((number == 1) and {"fp.lane"} or {"fp.lanes"})

    elseif view_name == "items_per_second_per_machine" then
        -- Show items/s/1 (machine) if it's a top level item
        local number_of_machines = (machine_count ~= nil) and machine_count or 1
        number = amount / timescale / number_of_machines

        local type_text = (item_type == "fluid") and {"fp.fluid"} or
          ((number == 1) and {"fp.item"} or {"fp.items"})
        -- Shows items/s/machine if a machine_count is given
        local per_machine = (machine_count ~= nil) and {"", "/", {"fp.machine"}} or ""
        appendage = {"", type_text, "/", {"fp.unit_second"}, per_machine}

    end

    -- If no number would be shown, but the amount is still tiny, adjust the number to be
    -- smaller than the margin of error, so it gets automatically hidden afterwards
    -- Kinda hacky way to do this, but doesn't matter probably ¯\_(ツ)_/¯
    if number == nil and amount < margin_of_error then number = margin_of_error - 1 end

    return number, appendage  -- number might be nil here
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
function ui_util.generate_module_effects_tooltip(effects, machine_proto)
    local localised_names = {
        consumption = {"fp.module_consumption"},
        speed = {"fp.module_speed"},
        productivity = {"fp.module_productivity"},
        pollution = {"fp.module_pollution"}
    }

    local tooltip = {""}
    for name, effect in pairs(effects) do
        if effect ~= 0 then
            local appendage = ""

            -- Handle effect caps and mining productivity if this is a machine-tooltip
            if machine_proto ~= nil then
                -- Consumption, speed and pollution are capped at -80%
                if (name == "consumption" or name == "speed" or name == "pollution") and effect < -0.8 then
                    effect = -0.8
                    appendage = {"", " (", {"fp.capped"}, ")"}

                -- Productivity can't go lower than 0
                elseif name == "productivity" then
                    if effect < 0 then
                        effect = 0
                        appendage = {"", " (", {"fp.capped"}, ")"}
                    end
                end
            end

            -- Force display of either a '+' or '-'
            local number = ("%+d"):format(math.floor((effect * 100) + 0.5))
            tooltip = {"", tooltip, "\n", localised_names[name], ": ", number, "%", appendage}
        end
    end

    if table_size(tooltip) > 1 then return {"", "\n", tooltip}
    else return tooltip end
end


-- ** Number formatting **
-- Formats given number to given number of significant digits
function ui_util.format_number(number, precision)
    if number == nil then return nil end

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
function ui_util.format_SI_value(value, unit, precision)
    local prefixes = {"", "kilo", "mega", "giga", "tera", "peta", "exa", "zetta", "yotta"}
    local units = {
        ["W"] = {"fp.unit_watt"},
        ["J"] = {"fp.unit_joule"},
        ["P/s"] = {"", {"fp.unit_pollution"}, "/", {"fp.unit_second"}}
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


-- **** Rate Limiting ****
ui_util.rate_limiting_events = {
    ["fp_floor_up"] = {timeout = 10},
    ["fp_confirm_dialog"] = {timeout = 20},
    [defines.events.on_player_selected_area] = {timeout = 20},
    ["filter_item_picker"] = {timeout = 6, handler = item_picker.handle_searchfield_change},
    ["submit_modal_dialog"] = {timeout = 20},
    [defines.events.on_gui_click] = {timeout = 10}
}

-- Returns whether the given event should be prevented from carrying out it's action due to rate limiting
function ui_util.rate_limiting_active(player, event_name, object_name)
    local last_action = get_ui_state(player).last_action
    local timeout = ui_util.rate_limiting_events[event_name].timeout
    local current_tick = game.tick

    -- Always allow action if there is no last_action or the ticks are paused
    local limiting_active = (table_size(last_action) > 0 and not game.tick_paused
      and event_name == last_action.event_name and object_name == last_action.object_name
      and (current_tick - last_action.tick) < timeout)

    -- Only update the last action if an action will indeed be carried out
    if not limiting_active then
        last_action.tick = current_tick
        last_action.event_name = event_name
        last_action.object_name = object_name
    end

    return limiting_active
end

-- Function to register an on_nth_tick to run the relevant handler once more after the last rate limiting occured
function ui_util.set_nth_tick_refresh(player, element)
    local last_action = get_ui_state(player).last_action
    local rate_limiting_event = ui_util.rate_limiting_events[last_action.event_name]
    local nth_tick = game.tick + rate_limiting_event.timeout

    -- Unregister the previous action as the new one will replace it
    if last_action.nth_tick then script.on_nth_tick(last_action.nth_tick, nil) end
    last_action.nth_tick = nth_tick
    last_action.element = element  -- needed to re-create the handler on_load

    script.on_nth_tick(nth_tick, function(event)
        rate_limiting_event.handler(element)
        last_action.nth_tick = nil
        last_action.element = nil
        script.on_nth_tick(event.nth_tick, nil)
    end)
end


-- ** Misc **
-- Returns string representing the given timescale (Currently only needs to handle 1 second/minute/hour)
function ui_util.format_timescale(timescale, raw, whole_word)
    local ts = nil
    if timescale == 1 then
        ts = whole_word and {"fp.second"} or {"fp.unit_second"}
    elseif timescale == 60 then
        ts = whole_word and {"fp.minute"} or {"fp.unit_minute"}
    elseif timescale == 3600 then
        ts = whole_word and {"fp.hour"} or {"fp.unit_hour"}
    end
    if raw then return ts
    else return {"", "1", ts} end
end

-- Formats the given 'modifier keys' to a clearer table
function ui_util.format_modifier_keys(direction, alt)
    return {
        shift = (direction == "positive"),
        control = (direction == "negative"),
        alt = alt
    }
end

-- Checks whether the archive is open; posts an error and returns true if it is
function ui_util.check_archive_status(player)
    if get_flags(player).archive_open then
        ui_util.message.enqueue(player, {"fp.error_editing_archived_subfactory"}, "error", 1, true)
        return true
    else
        return false
    end
end

-- Executes an alt-action on the given action_type and data
function ui_util.execute_alt_action(player, action_type, data)
    local alt_action = get_settings(player).alt_action

    local remote_action = remote_actions[alt_action]
    if remote_action ~= nil and remote_action[action_type] then
        remote_actions[action_type](player, alt_action, data)
    end
end

-- Tries to find the currently open modal dialog and returns it
function ui_util.find_modal_dialog(player)
    local modal_dialog_type = get_ui_state(player).modal_dialog_type
    if modal_dialog_type == nil then
        return nil
    else
        local candidate_frame_name = "fp_frame_modal_dialog_" .. modal_dialog_type
        return player.gui.screen[candidate_frame_name] or player.gui.screen["fp_frame_modal_dialog"]
    end
end


-- **** Context ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function ui_util.context.create(player)
    return {
        factory = global.players[player.index].factory,
        subfactory = nil,
        floor = nil,
        line = nil
    }
end

-- Updates the context to match the newly selected factory
function ui_util.context.set_factory(player, factory)
    local context = get_context(player)
    context.factory = factory
    local subfactory = factory.selected_subfactory or
      Factory.get_by_gui_position(factory, "Subfactory", 1)  -- might be nil
    ui_util.context.set_subfactory(player, subfactory)
end

-- Updates the context to match the newly selected subfactory
function ui_util.context.set_subfactory(player, subfactory)
    local context = get_context(player)
    context.factory.selected_subfactory = subfactory
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
    context.line = nil
end

-- Updates the context to match the newly selected floor
function ui_util.context.set_floor(player, floor)
    local context = get_context(player)
    context.subfactory.selected_floor = floor
    context.floor = floor
    context.line = nil
end


-- **** Attributes ****
-- Returns a tooltip containing the attributes of the given beacon prototype
function ui_util.attributes.beacon(beacon)
    return {"", {"fp.module_slots"}, ": " .. beacon.module_limit .. "\n",
           {"fp.effectivity"}, ": " .. (beacon.effectivity * 100) .. "%\n",
           {"fp.energy_consumption"}, ": ", ui_util.format_SI_value(beacon.energy_usage, "W", 3)}
end

-- Returns a tooltip containing the attributes of the given fuel prototype
function ui_util.attributes.fuel(fuel)
    return {"", {"fp.fuel_value"}, ": ", ui_util.format_SI_value(fuel.fuel_value, "J", 3), "\n",
           {"fp.emissions_multiplier"}, ": " .. fuel.emissions_multiplier}
end

-- Returns a tooltip containing the attributes of the given belt prototype
function ui_util.attributes.belt(belt)
    return {"", {"fp.throughput"}, ": " .. belt.throughput .. " ", {"fp.items"}, "/", {"fp.unit_second"}}
end

-- Returns a tooltip containing the attributes of the given machine prototype
function ui_util.attributes.machine(machine)
    local energy_usage = machine.energy_usage * 60
    return {"", {"fp.crafting_speed"}, ": " .. ui_util.format_number(machine.speed, 4) .. "\n",
           {"fp.energy_consumption"}, ": ", ui_util.format_SI_value(energy_usage, "W", 3), "\n",
           {"fp.cpollution"}, ": ", ui_util.format_SI_value(energy_usage * machine.emissions, "P/s", 3), "\n",
           {"fp.module_slots"}, ": " .. machine.module_limit}
end


-- **** Switch utility ****
-- Adds an on/off-switch including a label with tooltip to the given flow
-- Automatically converts boolean state to the appropriate switch_state
function ui_util.switch.add_on_off(parent_flow, name, state, caption, tooltip)
    if type(state) == "boolean" then state = ui_util.switch.convert_to_state(state) end

    local flow = parent_flow.add{type="flow", name="flow_" .. name, direction="horizontal"}
    flow.style.vertical_align = "center"

    local switch = flow.add{type="switch", name="fp_switch_" .. name, switch_state=state,
      left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}

    caption = (tooltip ~= nil) and {"", caption, " [img=info]"} or caption
    local label = flow.add{type="label", name="label_" .. name, caption=caption, tooltip=tooltip}
    label.style.font = "fp-font-15p"
    label.style.left_margin = 8

    return switch
end

-- Returns the switch_state of the switch by the given name in the given flow (optionally as a boolean)
function ui_util.switch.get_state(flow, name, boolean)
    local state = flow["flow_" .. name]["fp_switch_" .. name].switch_state
    if boolean then return ui_util.switch.convert_to_boolean(state)
    else return state end
end

-- Sets the switch_state of the switch by the given name in the given flow (state given as switch_state or boolean)
function ui_util.switch.set_state(flow, name, state)
    if type(state) == "boolean" then state = ui_util.switch.convert_to_state(state) end
    flow["flow_" .. name]["fp_switch_" .. name].switch_state = state
end

function ui_util.switch.convert_to_boolean(state)
    return (state == "left") and true or false
end

function ui_util.switch.convert_to_state(boolean)
    return boolean and "left" or "right"
end


-- **** Messages ****
-- Enqueues the given message into the message queue
-- Possible types are error, warning, hint
function ui_util.message.enqueue(player, message, type, lifetime, instant_refresh)
    table.insert(get_ui_state(player).message_queue, {text=message, type=type, lifetime=lifetime})
    if instant_refresh then ui_util.message.refresh(player) end
end

-- Refreshes the current message, taking into account priotities and lifetimes
-- The messages are displayed in enqueued order, displaying higher priorities first
-- The lifetime is decreased for every message on every refresh
-- (The algorithm(s) could be more efficient, but it doesn't matter for the small dataset)
function ui_util.message.refresh(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if main_dialog == nil then return end
    local flow_titlebar = main_dialog["flow_titlebar"]
    if flow_titlebar == nil then return end

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
        for _, message in pairs(ui_state.message_queue) do
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
    for index, message in pairs(ui_state.message_queue) do
        message.lifetime = message.lifetime - 1
        if message.lifetime <= 0 then ui_state.message_queue[index] = nil end
    end

    local label_hint = flow_titlebar["label_titlebar_hint"]
    label_hint.caption = new_message
    ui_util.set_label_color(label_hint, new_color)
end
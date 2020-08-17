require("mod-gui")

ui_util = {
    mod_gui = {},
    context = {},
    switch = {}
}


-- ** GUI utilities **
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


-- ** Tooltips **
-- File-local to so this dict isn't recreated on every call of the function following it
local valid_alt_types = {tl_ingredient=true, tl_product=true, tl_byproduct=true, recipe=true,
  product=true, byproduct=true, ingredient=true, fuel=true}

-- Either adds the tutorial tooltip to the button, or returns it if none is given
function ui_util.tutorial_tooltip(player, button, tut_type, line_break)
    local player_table = data_util.get("table", player)

    if player_table.preferences.tutorial_mode then
        local b = line_break and "\n\n" or ""
        local alt_action = player_table.settings.alt_action
        local f = (valid_alt_types[tut_type] and alt_action ~= "none")
          and {"fp.tut_alt_action", {"fp.alt_action_" .. alt_action}} or ""
        if button ~= nil then
            button.tooltip = {"", button.tooltip, b, {"fp.tut_mode"}, "\n", {"fp.tut_" .. tut_type}, f}
        else
            return {"", b, {"fp.tut_mode"}, "\n", {"fp.tut_" .. tut_type}, f}
        end

    elseif button == nil then  -- return empty string if there should be a return value
        return ""
    end
end

-- Determines the raw amount and the text-appendage for the given item (spec. by type, amount)
function ui_util.determine_item_amount_and_appendage(player, view_name, item_type, amount, machine)
    local timescale = get_context(player).subfactory.timescale
    local number, appendage = nil, ""

    if view_name == "items_per_timescale" then
        number = amount

        local type_text = (item_type == "fluid") and {"fp.fluid"} or
          ((number == 1) and {"fp.item"} or {"fp.items"})
        appendage = {"", type_text, "/", ui_util.format_timescale(timescale, true, false)}

    elseif view_name == "belts_or_lanes" and item_type ~= "fluid" then
        local throughput = prototyper.defaults.get(player, "belts").throughput
        local show_belts = (get_settings(player).belts_or_lanes == "belts")
        local divisor = (show_belts) and throughput or (throughput / 2)
        number = amount / divisor / timescale

        appendage = (show_belts) and ((number == 1) and {"fp.belt"} or {"fp.belts"}) or
          ((number == 1) and {"fp.lane"} or {"fp.lanes"})

    elseif view_name == "items_per_second_per_machine" then
        -- Show items/s/1 (machine) if it's a top level item
        local number_of_machines = (machine ~= nil) and machine.count or 1
        number = amount / timescale / number_of_machines

        local type_text = (item_type == "fluid") and {"fp.fluid"} or
          ((number == 1) and {"fp.item"} or {"fp.items"})
        -- Shows items/s/machine if a machine_count is given
        local per_machine = (machine ~= nil) and {"", "/", {"fp.machine"}} or ""
        appendage = {"", type_text, "/", {"fp.unit_second"}, per_machine}

    end

    -- If no number would be shown, but the amount is still tiny, adjust the number to be
    -- smaller than the margin of error, so it gets automatically hidden afterwards
    -- Kinda hacky way to do this, but doesn't matter probably ¯\_(ツ)_/¯
    if number == nil and amount < MARGIN_OF_ERROR then number = MARGIN_OF_ERROR - 1 end

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

-- Checks whether the archive is open; posts an error and returns true if it is
function ui_util.check_archive_status(player)
    if data_util.get("flags", player).archive_open then
        titlebar.enqueue_message(player, {"fp.error_editing_archived_subfactory"}, "error", 1, true)
        return true
    else
        return false
    end
end

-- Returns first whether the icon is missing, then the rich text for it
function ui_util.verify_subfactory_icon(subfactory)
    local icon = subfactory.icon
    local type = (icon.type == "virtual") and "virtual-signal" or icon.type
    local subfactory_sprite = type .. "/" .. icon.name

    if not game.is_valid_sprite_path(subfactory_sprite) then
        return true, ("[img=utility/missing_icon]")
    else
        return false, ("[img=" .. subfactory_sprite .. "]")
    end
end

-- Returns the attribute string for the given prototype
-- Could figure out structure type itself, but that's slower
function ui_util.get_attributes(type, prototype)
    local all_prototypes = global["all_" .. type]

    if all_prototypes.structure_type == "simple" then
        return PROTOTYPE_ATTRIBUTES[type][prototype.id]
    else  -- structure_type == "complex"
        local category_id = all_prototypes.map[prototype.category]
        return PROTOTYPE_ATTRIBUTES[type][category_id][prototype.id]
    end
end

-- Executes an alt-action on the given action_type and data
function ui_util.execute_alt_action(player, action_type, data)
    local alt_action = data_util.get("settings", player).alt_action

    local remote_action = remote_actions[alt_action]
    if remote_action ~= nil and remote_action[action_type] then
        remote_actions[action_type](player, alt_action, data)
    end
end

-- Resets the selected subfactory to a valid position after one has been removed
function ui_util.reset_subfactory_selection(player, factory, removed_gui_position)
    if removed_gui_position > factory.Subfactory.count then removed_gui_position = removed_gui_position - 1 end
    local subfactory = Factory.get_by_gui_position(factory, "Subfactory", removed_gui_position)
    ui_util.context.set_subfactory(player, subfactory)
end


-- **** Mod-GUI ****
-- Create the always-present GUI button to open the main dialog
function ui_util.mod_gui.create(player)
    local frame_flow = mod_gui.get_button_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add{type="button", name="fp_button_toggle_interface", caption="FP", tooltip={"fp.open_main_dialog"},
          style=mod_gui.button_style, mouse_button_filter={"left"}}
    end

    frame_flow["fp_button_toggle_interface"].visible = data_util.get("settings", player).show_gui_button
end

-- Toggles the visibility of the toggle-main-dialog-button
function ui_util.mod_gui.toggle(player)
    local enable = data_util.get("settings", player).show_gui_button
    mod_gui.get_button_flow(player)["fp_button_toggle_interface"].visible = enable
end


-- **** Context ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function ui_util.context.create(player)
    return {
        factory = global.players[player.index].factory,
        subfactory = nil,
        floor = nil
    }
end

-- Updates the context to match the newly selected factory
function ui_util.context.set_factory(player, factory)
    local context = data_util.get("context", player)
    context.factory = factory
    local subfactory = factory.selected_subfactory or
      Factory.get_by_gui_position(factory, "Subfactory", 1)  -- might be nil
    ui_util.context.set_subfactory(player, subfactory)
end

-- Updates the context to match the newly selected subfactory
function ui_util.context.set_subfactory(player, subfactory)
    local context = data_util.get("context", player)
    context.factory.selected_subfactory = subfactory
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
end

-- Updates the context to match the newly selected floor
function ui_util.context.set_floor(player, floor)
    local context = data_util.get("context", player)
    context.subfactory.selected_floor = floor
    context.floor = floor
end


-- **** Switch utility ****
-- Adds an on/off-switch including a label with tooltip to the given flow
-- Automatically converts boolean state to the appropriate switch_state
function ui_util.switch.add_on_off(parent_flow, name, state, caption, tooltip, label_first)
    if type(state) == "boolean" then state = ui_util.switch.convert_to_state(state) end

    local flow = parent_flow.add{type="flow", name="flow_" .. name, direction="horizontal"}
    flow.style.vertical_align = "center"
    local switch, label

    local function add_switch()
        switch = flow.add{type="switch", name="fp_switch_" .. name, switch_state=state,
          left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}
    end

    local function add_label()
        caption = (tooltip ~= nil) and {"", caption, " [img=info]"} or caption
        label = flow.add{type="label", name="label_" .. name, caption=caption, tooltip=tooltip}
        label.style.font = "fp-font-15p"
    end

    if label_first then add_label(); add_switch(); label.style.right_margin = 8
    else add_switch(); add_label(); label.style.left_margin = 8 end

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
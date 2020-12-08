mod_gui = require("mod-gui")

ui_util = {
    mod_gui = {},
    context = {},
    switch = {}
}

-- ** GUI **
-- Properly centers the given frame (need width/height parameters cause no API-read exists)
function ui_util.properly_center_frame(player, frame, dimensions)
    local resolution, scale = player.display_resolution, player.display_scale
    local x_offset = ((resolution.width - (dimensions.width * scale)) / 2)
    local y_offset = ((resolution.height - (dimensions.height * scale)) / 2)
    frame.location = {x_offset, y_offset}
end

-- Sets basic attributes on the given textfield
function ui_util.setup_textfield(textfield)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
end

-- Sets up the given textfield as a numeric one, with the specified options
function ui_util.setup_numeric_textfield(textfield, decimal, negative)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
    textfield.numeric = true
    textfield.allow_decimal = (decimal or false)
    textfield.allow_negative = (negative or false)
end

-- Focuses and selects all the text of the given textfield
function ui_util.select_all(textfield)
    textfield.focus()
    textfield.select_all()
end


-- ** MISC **
function ui_util.generate_tutorial_tooltip(player, element_type, has_alt_action, add_padding, avoid_archive)
    local player_table = data_util.get("table", player)

    local archive_check = (avoid_archive and player_table.ui_state.flags.archive_open)
    if player_table.preferences.tutorial_mode and not archive_check then
        local action_tooltip = {"fp.tut_mode_" .. element_type}

        local alt_action_name, alt_action_tooltip = player_table.settings.alt_action, ""
        if has_alt_action and alt_action_name ~= "none" then
            alt_action_tooltip = {"fp.tut_mode_alt_action", {"fp.alt_action_" .. alt_action_name}}
        end

        local padding = (add_padding) and {"fp.tut_mode_tooltip_padding"} or ""
        return {"fp.tut_mode_tooltip", padding, action_tooltip, alt_action_tooltip}
    else
        return ""
    end
end

function ui_util.check_archive_status(player)
    if data_util.get("flags", player).archive_open then
        title_bar.enqueue_message(player, {"fp.error_editing_archived_subfactory"}, "error", 1, true)
        return false
    else
        return true
    end
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


-- **** Mod-GUI ****
-- Create the always-present GUI button to open the main dialog
function ui_util.mod_gui.create(player)
    local frame_flow = mod_gui.get_button_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add{type="button", name="fp_button_toggle_interface", caption={"fp.toggle_interface"},
          tooltip={"fp.toggle_interface_tt"}, style=mod_gui.button_style, mouse_button_filter={"left"}}
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
        label.style.font = "default-semibold"
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
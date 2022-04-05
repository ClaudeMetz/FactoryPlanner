mod_gui = require("mod-gui")

ui_util = {
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

function ui_util.setup_textfield(textfield)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
end

function ui_util.setup_numeric_textfield(textfield, decimal, negative)
    textfield.lose_focus_on_confirm = true
    textfield.clear_and_focus_on_right_click = true
    textfield.numeric = true
    textfield.allow_decimal = (decimal or false)
    textfield.allow_negative = (negative or false)
end

function ui_util.select_all(textfield)
    textfield.focus()
    textfield.select_all()
end

-- Toggles the visibility of the toggle-main-dialog-button
function ui_util.toggle_mod_gui(player)
    local enable = data_util.get("settings", player).show_gui_button

    local frame_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = frame_flow["fp_button_toggle_interface"]

    if enable then
        if not mod_gui_button then
            frame_flow.add{type="button", name="fp_button_toggle_interface", caption={"fp.toggle_interface"},
              tooltip={"fp.toggle_interface_tt"}, tags={mod="fp", on_gui_click="mod_gui_toggle_interface"},
              style=mod_gui.button_style, mouse_button_filter={"left"}}
        end
    else
        if mod_gui_button then mod_gui_button.destroy() end
    end
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

-- Formats given number to fixed number of significant digits based on icon size, using ceil rounding
function ui_util.format_number_ceil(number)
    if number == nil then return nil end

    -- Set very small numbers to 0
    if number < 0.0001 then
        return 0
    end

    -- Figure out how many decimals we have
    local base_decimals = math.floor(math.log10(number))
    -- Example 1 for the sake of documentation: pretend our number is 23456.78912
    -- base_decimals is math.floor(4.3702) = 4
    -- Example 2 for the sake of documentation: pretend our number is 999.9
    -- base_decimals is math.floor(2.99995656838) = 2

    -- Visual example of the mapping we intend:
    -- decimals = -2 ->  .0234567891  ->  0.1  (we just round up to 0.1)
    -- decimals = -1 ->  .2345678912  ->  0.2  (one decimal of data)
    -- decimals = 0  ->  2.345678912  ->  2.4  (two decimals of data)
    -- decimals = 1  ->  23.45678912  ->  23.5 (three decimals of data)
    -- decimals = 2  ->  234.5678912  ->  235  (three decimals of data)
    -- decimals = 3  ->  2345.678912  ->  2.4k (two decimals of data)
    -- decimals = 4  ->  23456.78912  ->  24k  (two decimals of data)
    -- decimals = 5  ->  234567.8912  ->  235k (three decimals of data)
    -- decimals = 6  ->  2345678.912  ->  2.4M (two decimals of data)
    -- decimals = 7  ->  23456789.12  ->  24M  (two decimals of data)
    -- decimals = 8  ->  234567891.2  ->  235M (three decimals of data)
    -- tl;dr: hardcoded result if it's <-1, one decimal if it's <0, three decimals if it's in [1, 2) or if (it%3) is in [2, 3), otherwise two
    local desired_decimals = 2
    if base_decimals < -1 then
        return "0.1"
    elseif base_decimals < 0 then
        desired_decimals = 1
    elseif base_decimals == 1 or base_decimals % 3 == 2 then
        desired_decimals = 3
    end
    -- Example 1: desired_decimals is 2
    -- Example 2: desired_decimals is 3

    -- Take the number, shove it down to our target, ceil it, and bring it back up
    local shift = (10 ^ (math.floor(base_decimals) - desired_decimals + 1))
    local shifted_number = number / shift
    -- Example 1: shifted_number is 23456.78912 / (10 ^ (4 - 2 + 1)) = 23456.78912 / (10 ^ 3) =  23.45678912
    -- Example 2: shifted_number is   999.9     / (10 ^ (2 - 3 + 1)) =   999.9     / (10 ^ 0) = 999.9

    -- Add a slight magic number adjustment to compensate for floating-point inaccuracy
    local ceiled_number = math.ceil(shifted_number - 0.00001)
    -- Example 1: ceiled_number is   24
    -- Example 2: ceiled_number is 1000

    -- Uhoh, we have a problem! In `math.ceil()`, example 2 has now gained a digit.
    -- But this is actually OK! It's gained a digit, but all digits aside from the first one are 0's.
    -- Factorio's formatting code is going to just do the right thing here.

    local returned_number = ceiled_number * shift
    -- Example 1: returned_number is 24000
    -- Example 2: returned_number is  1000

    -- This is just to add a decimal at the end if it's not an actual perfect round (plus or minus an epsilon value)
    if math.abs(number - returned_number) > 0.00001 then
        returned_number = returned_number + 0.00001
    end

    return returned_number
end

local function format_number_tests()
    local errlist = ""
    local function check(input, expected)
        local result = ui_util.format_number_ceil(input)
        if math.abs(result - expected) > 0.000001 then -- less than the final adjustment value
            errlist = errlist .. ("%f -> %f, should be %f\n"):format(input, result, expected)
        end
    end

    check(0, 0)
    check(0.1, 0.1)
    check(0.08, 0.1)    -- doesn't get the added decimal addition because it drops out much earlier
    check(0.002, 0.1)   -- doesn't get the added decimal addition because it drops out much earlier
    check(23456.78912, 24000.00001)
    check(1000, 1000)
    check(3, 3)
    check(2.99999, 3.00001)
    check(3.5, 3.5)
    check(3.56, 3.60001)
    check(0.123, 0.20001)
    check(999, 999)
    check(999.9, 1000.00001)

    if errlist ~= "" then
        error(errlist)
    end
end
format_number_tests()

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
function ui_util.switch.add_on_off(parent_flow, action, additional_tags, state, caption, tooltip, label_first)
    if type(state) == "boolean" then state = ui_util.switch.convert_to_state(state) end

    local flow = parent_flow.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"
    local switch, label

    local function add_switch()
        local tags = {mod="fp", on_gui_switch_state_changed=action}
        for key, value in pairs(additional_tags) do tags[key] = value end
        switch = flow.add{type="switch", tags=tags, switch_state=state,
          left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}
    end

    local function add_label()
        caption = (tooltip ~= nil) and {"", caption, " [img=info]"} or caption
        label = flow.add{type="label", caption=caption, tooltip=tooltip}
        label.style.font = "default-semibold"
    end

    if label_first then add_label(); add_switch(); label.style.right_margin = 8
    else add_switch(); add_label(); label.style.left_margin = 8 end

    return switch
end

function ui_util.switch.convert_to_boolean(state)
    return (state == "left") and true or false
end

function ui_util.switch.convert_to_state(boolean)
    return boolean and "left" or "right"
end

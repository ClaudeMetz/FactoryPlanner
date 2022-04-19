local mod_gui = require("mod-gui")

ui_util = {
    context = {},
    clipboard = {},
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


function ui_util.create_flying_text(player, text)
    player.create_local_flying_text{text=text, create_at_cursor=true}
end

function ui_util.create_cursor_blueprint(player, blueprint_entities)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="fp_cursor_blueprint"}
    blank_slot.set_blueprint_entities(blueprint_entities)
    player.add_to_clipboard(blank_slot)
    player.activate_paste()
    script_inventory.destroy()
end


-- This function is only called when Recipe Book is active, so no need to check for the mod
function ui_util.open_in_recipebook(player, type, name)
    local message = nil

    if remote.call("RecipeBook", "version") ~= RECIPEBOOK_API_VERSION then
        message = {"fp.error_recipebook_version_incompatible"}
    else
        local was_opened = remote.call("RecipeBook", "open_page", player.index, type, name)
        if not was_opened then message = {"fp.error_recipebook_lookup_failed", {"fp.pl_" .. type, 1}} end
    end

    if message then title_bar.enqueue_message(player, message, "error", 1, true) end
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

-- Destroys the toggle-main-dialog-button if present
function ui_util.destroy_mod_gui(player)
    local mod_gui_button = mod_gui.get_button_flow(player)["fp_button_toggle_interface"]
    if mod_gui_button then mod_gui_button.destroy() end
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



-- ** Context **
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


-- ** CLIPBOARD **
-- Copies the given object into the player's clipboard as a packed object
function ui_util.clipboard.copy(player, object)
    local player_table = data_util.get("table", player)
    player_table.clipboard = {
        class = object.class,
        object = _G[object.class].pack(object)
    }
    ui_util.create_flying_text(player, {"fp.copied_into_clipboard", {"fp.pu_" .. object.class:lower(), 1}})
end

-- Tries pasting the player's clipboard content onto the given target
function ui_util.clipboard.paste(player, target)
    local player_table = data_util.get("table", player)
    local clip = player_table.clipboard

    if clip == nil then
        ui_util.create_flying_text(player, {"fp.clipboard_empty"})
    else
        -- Create a clone to paste by unpacking the clip, which creates a new independent object
        local clone = _G[clip.class].unpack(clip.object)
        clone.parent = target.parent
        _G[clip.class].validate(clip.object)

        local success, error = _G[target.class].paste(target, clone)
        if success then  -- objects in the clipboard are always valid since it resets on_config_changed
            ui_util.create_flying_text(player, {"fp.pasted_from_clipboard", {"fp.pu_" .. clip.class:lower(), 1}})

            calculation.update(player, player_table.ui_state.context.subfactory)
            main_dialog.refresh(player, "subfactory")
        else
            local object_lower, target_lower = {"fp.pl_" .. clip.class:lower(), 1}, {"fp.pl_" .. target.class:lower(), 1}
            if error == "incompatible_class" then
                ui_util.create_flying_text(player, {"fp.clipboard_incompatible_class", object_lower, target_lower})
            elseif error == "incompatible" then
                ui_util.create_flying_text(player, {"fp.clipboard_incompatible", object_lower})
            elseif error == "already_exists" then
                ui_util.create_flying_text(player, {"fp.clipboard_already_exists", target_lower})
            elseif error == "no_empty_slots" then
                ui_util.create_flying_text(player, {"fp.clipboard_no_empty_slots"})
            elseif error == "recipe_irrelevant" then
                ui_util.create_flying_text(player, {"fp.clipboard_recipe_irrelevant"})
            end
        end
    end
end


-- ** Switch utility **
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

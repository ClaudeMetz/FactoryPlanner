-- Sets up global data structure of the mod
script.on_init(function()
    data_init()
end)


-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.players[event.player_index]
    -- Sets up the always-present GUI button for open/close
    gui_init(player)
    -- Incorporates the mod setting for the button
    toggle_button_interface(player)
end)


-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    local player = game.players[event.player_index]
    toggle_button_interface(player)
end)


-- Fires on pressing of the custom 'Open/Close' shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.players[event.player_index]
    toggle_main_dialog(player)
end)

-- Fires on pressing the custom 'Confirm' shortcut to confirm the subfactory dialog
script.on_event("fp_confirm", function(event)
    local player = game.players[event.player_index]
    local subfactory_dialog = player.gui.center["subfactory_dialog"]
    if subfactory_dialog then
        close_subfactory_dialog(player, true)
    end
end)


-- Fires on any click on a GUI element
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.players[event.player_index]
    local is_left_click = is_left_click(event)
    
    -- Unfocuses textfield when any other element in the dialog is clicked (buggy, see BUGS)
    if player.gui.center["subfactory_dialog"] and event.element.name ~= "textfield_subfactory_name" then
        player.gui.center["subfactory_dialog"].focus()
    end


    local button_matched = false

    -- Reacts to the delete button being pressed
    if event.element.name == "button_delete_subfactory" and is_left_click then
        handle_subfactory_deletion(player, true)
        button_matched = true
    else
        -- Resets delete button if any other button is pressed
        handle_subfactory_deletion(player, false)
    end

    local refresh = false
    -- Changes the timescale of the current subfactory
    if string.find(event.element.name, "^button_timescale_%d+$") and is_left_click then
        local timescale = tonumber(string.match(event.element.name, "%d+"))
        change_subfactory_timescale(player, timescale)
        button_matched = true
    else
        -- Resets changing timescale buttons if any other button is pressed
        global["currently_changing_timescale"] = false
        -- Initiates info pane refresh at the end of the listeners
        refresh = true
    end

    
    -- If any of the buttons previously checked have been matched, this part doesn't need to run
    if not button_matched then
        -- Reacts to the always-present GUI button or the close-button on the main dialog being pressed
        if event.element.name == "fp_button_toggle_interface" or event.element.name == "button_titlebar_exit" and
          is_left_click then
            toggle_main_dialog(player)
        
        -- Opens the new-subfactory dialog
        elseif event.element.name == "button_new_subfactory" and is_left_click then
            open_subfactory_dialog(player, false)

        -- Opens the edit-subfactory dialog
        elseif event.element.name == "button_edit_subfactory" and is_left_click then
            open_subfactory_dialog(player, true)

        -- Closes the subfactory dialog
        elseif event.element.name == "button_subfactory_cancel" and is_left_click then
            close_subfactory_dialog(player, false)

        -- Submits the subfactory dialog
        elseif event.element.name == "button_subfactory_submit" and is_left_click then
            close_subfactory_dialog(player, true)

        -- Enters mode to change the timescale of the current subfactory
        elseif event.element.name == "button_change_timescale" and is_left_click then
            global["currently_changing_timescale"] = true
            refresh_info_pane(player)
        
        -- Reacts to a subfactory button being pressed
        elseif string.find(event.element.name, "^xbutton_subfactory_%d+$") and not event.alt and
          event.button ~= defines.mouse_button_type.right then
            local id = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_element_click(player, id, event.control, event.shift)

        end
    end

    -- Refreshes info pane at the end to prevent reloading of elements that might be 
    -- clicked above (related to timescale setting)
    if refresh then refresh_info_pane(player) end
end)


-- Returns true only when the left mouse button (with no modifiers) has been pressed
function is_left_click(event)
    if event.button == defines.mouse_button_type.left and
      not event.alt and not event.control and not event.shift then
        return true
    else
        return false
    end
end

-- Returns true only when the right mouse button (with no modifiers) has been pressed
function is_right_click(event)
    if event.button == defines.mouse_button_type.right and
      not event.alt and not event.control and not event.shift then
        return true
    else
        return false
    end
end
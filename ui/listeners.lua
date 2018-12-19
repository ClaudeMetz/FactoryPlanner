-- Fires when a player joins
script.on_event(defines.events.on_player_created, function(event)
    -- Create main-dialog GUI button
    local player = game.players[event.player_index]
    gui_init(player)
end)

-- Fires on pressing of the custom 'Open/Close' shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    -- Toggle the main dialog
    local player = game.players[event.player_index]
    toggle_main_dialog(player)
end)

-- Fires on pressing the custom 'Confirm' shortcut to confirm dialogs
script.on_event("fp_confirm", function(event)
    local player = game.players[event.player_index]

    -- Confirms the new/edit subfactory dialog
    local subfactory_dialog = player.gui.center["subfactory_dialog"]
    if subfactory_dialog then
        close_subfactory_dialog(player, true)
    end
end)


-- Fires on all clicks on the GUI
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.players[event.player_index]
    local is_left_click = is_left_click(event)
    
    -- Unfocuses textfield when any other element in the dialog is clicked (buggy, see BUGS)
    if player.gui.center["subfactory_dialog"] and event.element.name ~= "textfield_subfactory_name" then
        player.gui.center["subfactory_dialog"].focus()
    end

    if event.element.name == "button_delete_subfactory" and is_left_click then
        handle_subfactory_deletion(player, true)
    else
        -- Resets button if any other button is pressed
        handle_subfactory_deletion(player, false)

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
        
        -- Reacts to a subfactory button being pressed
        elseif string.find(event.element.name, "^xbutton_subfactory_%d+$") and not event.alt and
          event.button ~= defines.mouse_button_type.right then
            local id = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_element_click(player, id, event.control, event.shift)
        end
    end
end)


-- Returns true when only the left mouse button has been pressed (no modifiers)
function is_left_click(event)
    if event.button == defines.mouse_button_type.left and
      not event.alt and not event.control and not event.shift then
        return true
    else
        return false
    end
end
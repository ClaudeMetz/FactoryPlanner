-- Sets up global data structure of the mod
script.on_init(function()
    data_init()
end)

-- Prompts a recipe dialog reload and a validity check on all subfactories
script.on_configuration_changed(function()
    global["mods_changed"] = true
    Factory.update_validity()
end)


-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.players[event.player_index]
    -- Sets up the always-present GUI button for open/close
    gui_init(player)
    -- Incorporates the mod setting for the visibility of the toggle-main-dialog-button
    toggle_button_interface(player)
end)


-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    local player = game.players[event.player_index]
    -- Adjusts the toggle-main-dialog-button
    toggle_button_interface(player)
end)


-- Fires on pressing of the custom 'Open/Close' shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.players[event.player_index]
    toggle_main_dialog(player)
end)


-- Fires on any radiobutton change
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.players[event.player_index]
    if string.find(event.element.name, "^fp_checkbox_filter_condition_%l+$") then
        apply_recipe_filter(player)
    end
end)

-- Fires on any click on a GUI element
script.on_event(defines.events.on_gui_click, function(event)
    local is_left_click = (event.button == defines.mouse_button_type.left and
                            not event.alt and not event.control and not event.shift)
    local is_right_click = (event.button == defines.mouse_button_type.right and
                             not event.alt and not event.control and not event.shift)

    local click, direction = nil, nil
    if is_left_click then click = "left" elseif is_right_click then click = "right" end
    if event.button == defines.mouse_button_type.left and (not event.alt) then
        if not event.control and event.shift then direction = "positive" 
        elseif event.control and not event.shift then direction = "negative" end
    end

    local player = game.players[event.player_index]
    
    -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
    if event.element.name == "fp_button_toggle_interface" or event.element.name == "fp_button_titlebar_exit"
        and is_left_click then
        toggle_main_dialog(player)

    -- Closes the modal dialog straight away
    elseif event.element.name == "fp_button_modal_dialog_cancel" and is_left_click then
        exit_modal_dialog(player, "cancel")

    -- Submits the modal dialog, forwarding to the appropriate function
    elseif event.element.name == "fp_button_modal_dialog_submit" and is_left_click then
        exit_modal_dialog(player, "submit")

    -- Closes the modal dialog, calling the appropriate deletion function
    elseif event.element.name == "fp_button_modal_dialog_delete" and is_left_click then
        exit_modal_dialog(player, "delete")
    
    -- Opens the new-subfactory dialog
    elseif event.element.name == "fp_button_new_subfactory" and is_left_click then
        enter_modal_dialog(player, "subfactory", true, false, {edit=false})

    -- Opens the edit-subfactory dialog
    elseif event.element.name == "fp_button_edit_subfactory" and is_left_click then
        enter_modal_dialog(player, "subfactory", true, false, {edit=true})

    -- Reacts to the delete button being pressed
    elseif event.element.name == "fp_button_delete_subfactory" and is_left_click then
        handle_subfactory_deletion(player)

    -- Enters mode to change the timescale of the current subfactory
    elseif event.element.name == "fp_button_change_timescale" and is_left_click then
        handle_subfactory_timescale_change(player, nil)

    -- Opens notes dialog
    elseif event.element.name == "fp_button_view_notes" and is_left_click then
        enter_modal_dialog(player, "notes", true, false)

    -- Opens the add-product dialog
    elseif event.element.name == "fp_sprite-button_add_product" and is_left_click then
        enter_modal_dialog(player, "product", true, false, {edit=false})

    -- Submits the entered search term in the recipe dialog
    elseif event.element.name == "fp_sprite-button_search_recipe" and is_left_click then
        apply_recipe_filter(player)

    -- Closes the recipe dialog without a selection having been made
    elseif event.element.name == "fp_button_recipe_dialog_cancel" and is_left_click then
        close_recipe_dialog(player, nil)

    -- Reacts to a subfactory button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_subfactory_%d+$") then
        local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
        handle_subfactory_element_click(player, subfactory_id, click, direction)

    -- Deletes invalid subfactory items/recipes after the error bar button has been pressed
    elseif string.find(event.element.name, "^fp_button_error_bar_%d+$") and is_left_click then
        local id = tonumber(string.match(event.element.name, "%d+"))
        Subfactory.remove_invalid_datasets(id)
        refresh_subfactory_bar(player)

    -- Changes the timescale of the current subfactory
    elseif string.find(event.element.name, "^fp_button_timescale_%d+$") and is_left_click then
        local timescale = tonumber(string.match(event.element.name, "%d+"))
        handle_subfactory_timescale_change(player, timescale)

    -- Reacts to a product button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_product_%d+$") then
        local product_id = tonumber(string.match(event.element.name, "%d+"))
        handle_product_element_click(player, product_id, click, direction)

    -- Reacts to a item group button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_item_group_[a-z-]+$") and is_left_click then
        local item_group_name = string.gsub(event.element.name, "fp_sprite%-button_item_group_", "")
        change_item_group_selection(player, item_group_name)

    -- Reacts to a recipe button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_recipe_[a-z-]+$") and is_left_click then
        local recipe_name = string.gsub(event.element.name, "fp_sprite%-button_recipe_", "")
        close_recipe_dialog(player, recipe_name)
    end
end)
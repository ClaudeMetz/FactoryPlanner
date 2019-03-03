-- Sets up global data structure of the mod
script.on_init(function()
    data_init()
end)

-- Prompts a recipe dialog reload and a validity check on all subfactories
script.on_configuration_changed(function()
    global["mods_changed"] = true
    global["undesirable_recipes"] = generate_undesirable_recipes()
    global["all_recipes"] = generate_all_recipes()
    data_util.update_all_machines()
    
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

    -- Toggles the visibility of the toggle-main-dialog-button
    if event.setting == "fp_display_gui_button" then 
        toggle_button_interface(player)

    -- Changes the width of the main dialog by regenerating it
    elseif event.setting == "fp_subfactory_items_per_row" then
        ui_util.recalculate_main_dialog_dimensions(player)
        reload_main_dialog(player)

    end
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

-- Fires on any changes to a textbox
script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = game.players[event.player_index]
    if string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
        apply_percentage_change(player, event.element)
        refresh_hint_message(player)
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
    local found = true
    
    -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
    if event.element.name == "fp_button_toggle_interface" or event.element.name == "fp_button_titlebar_exit"
        and is_left_click then
        toggle_main_dialog(player)

    -- Closes the modal dialog straight away
    elseif event.element.name == "fp_button_modal_dialog_cancel" and is_left_click then
        exit_modal_dialog(player, "cancel")

    -- Closes the modal dialog, calling the appropriate deletion function
    elseif event.element.name == "fp_button_modal_dialog_delete" and is_left_click then
        exit_modal_dialog(player, "delete")

    -- Submits the modal dialog, forwarding to the appropriate function
    elseif event.element.name == "fp_button_modal_dialog_submit" and is_left_click then
        exit_modal_dialog(player, "submit")

    -- Opens the preferences dialog
    elseif event.element.name == "fp_button_titlebar_preferences" and is_left_click then
        enter_modal_dialog(player, "preferences", {close=true}, {})
    
    -- Opens the new-subfactory dialog
    elseif event.element.name == "fp_button_new_subfactory" and is_left_click then
        enter_modal_dialog(player, "subfactory", {submit=true}, {edit=false})

    -- Opens the edit-subfactory dialog
    elseif event.element.name == "fp_button_edit_subfactory" and is_left_click then
        enter_modal_dialog(player, "subfactory", {submit=true, delete=true}, {edit=true})

    -- Reacts to the delete button being pressed
    elseif event.element.name == "fp_button_delete_subfactory" and is_left_click then
        handle_subfactory_deletion(player)

    -- Enters mode to change the timescale of the current subfactory
    elseif event.element.name == "fp_button_change_timescale" and is_left_click then
        handle_subfactory_timescale_change(player, nil)

    -- Opens notes dialog
    elseif event.element.name == "fp_button_view_notes" and is_left_click then
        enter_modal_dialog(player, "notes", {submit=true}, {edit=false})

    -- Opens the add-product dialog
    elseif event.element.name == "fp_sprite-button_add_product" and is_left_click then
        enter_modal_dialog(player, "product", {submit=true}, {edit=false})

    -- Submits the entered search term in the recipe dialog
    elseif event.element.name == "fp_sprite-button_search_recipe" and is_left_click then
        apply_recipe_filter(player)

    -- Closes the recipe dialog without a selection having been made
    elseif event.element.name == "fp_button_recipe_dialog_cancel" and is_left_click then
        close_recipe_dialog(player, nil)

    -- Sets the selected floor to be the parent of the currently selected one
    elseif event.element.name == "fp_button_floor_up" and is_left_click then
        Subfactory.change_selected_floor(global["selected_subfactory_id"], "up")
        refresh_production_pane(player)

    -- Sets the selected floor to be the top one
    elseif event.element.name == "fp_button_floor_top" and is_left_click then
        Subfactory.change_selected_floor(global["selected_subfactory_id"], "top")
        refresh_production_pane(player)

    -- Reacts to a subfactory button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_subfactory_%d+$") then
        local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
        handle_subfactory_element_click(player, subfactory_id, click, direction)

    -- Deletes invalid subfactory items/recipes after the error bar button has been pressed
    elseif string.find(event.element.name, "^fp_button_error_bar_%d+$") and is_left_click then
        local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
        Subfactory.remove_invalid_datasets(subfactory_id)
        refresh_subfactory_bar(player, true)

    -- Changes the timescale of the current subfactory
    elseif string.find(event.element.name, "^fp_button_timescale_%d+$") and is_left_click then
        local timescale = tonumber(string.match(event.element.name, "%d+"))
        handle_subfactory_timescale_change(player, timescale)

    -- Reacts to a item group button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_item_group_[a-z-]+$") and is_left_click then
        local item_group_name = string.gsub(event.element.name, "fp_sprite%-button_item_group_", "")
        change_item_group_selection(player, item_group_name)

    -- Reacts to a recipe button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_recipe_[a-z-]+$") and is_left_click then
        local recipe_name = string.gsub(event.element.name, "fp_sprite%-button_recipe_", "")
        close_recipe_dialog(player, recipe_name)
    
    -- Reacts to any subfactory_pane item button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_subpane_[a-z-]+_%d+$") then
        local split_string = ui_util.split(event.element.name, "_")
        _G["handle_" .. split_string[4] .. "_element_click"](player, split_string[5], click, direction)

    -- Reacts to the recipe button on an (assembly) line being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_line_recipe_%d+$") then
        local line_id = tonumber(string.match(event.element.name, "%d+"))
        handle_line_recipe_click(player, line_id, click, direction)

    -- Reacts to the machine button on an (assembly) line being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_line_machine_%d+$") then
        local line_id = tonumber(string.match(event.element.name, "%d+"))
        handle_machine_change(player, line_id, nil, click, direction)
        
    -- Changes the machine of the selected (assembly) line
    elseif string.find(event.element.name, "^fp_sprite%-button_line_%d+_machine_[a-z0-9-]+$") then
        local split_string = ui_util.split(event.element.name, "_")
        handle_machine_change(player, split_string[4], split_string[6], click, direction)

    -- Reacts to any preferences machine button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_preferences_machine_[a-z0-9-]+_[a-z0-9-]+$") then
        local split_string = ui_util.split(event.element.name, "_")
        change_machine_preference(player, split_string[5], split_string[6])

    -- Reacts to any (assembly) line item button being pressed
    elseif string.find(event.element.name, "^fp_sprite%-button_line_[a-z]+_%d+_[a-z-]+$") and is_left_click then
        local split_string = ui_util.split(event.element.name, "_")
        handle_item_button_click(player, split_string[4], split_string[5], split_string[6])
        
    else found = false end

    -- Only reset hint if one of this mod's actual controls is pressed
    if found == true then 
        refresh_hint_message(player)
    -- Else remove focus from textfield so keyboard shortcuts work (not super reliable)
    elseif not string.find(event.element.name, "^fp_textfield_[a-z0-9-_]+$") then
        player.gui.center["fp_main_dialog"].focus() 
    end
end)
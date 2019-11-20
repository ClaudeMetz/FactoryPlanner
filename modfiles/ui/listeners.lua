require("ui.util")
require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")

-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    -- This mod currently only uses runtime-per-user settings
    if event.setting_type == "runtime-per-user" then
        local player = game.get_player(event.player_index)

        -- Reload all user mod settings
        reload_settings(player)

        -- Toggles the visibility of the toggle-main_dialog-button
        if event.setting == "fp_display_gui_button" then 
            toggle_button_interface(player)

        -- Redoes the calculations for ingredient satisfaction
        elseif event.setting == "fp_performance_mode" then
            calculation.update(player, get_context(player).subfactory)

        -- Changes the width of the main dialog
        elseif event.setting == "fp_subfactory_items_per_row" or
          event.setting == "fp_floor_recipes_at_once" then
            refresh_main_dialog(player, true)

        -- Refreshes the view selection or recipe machine buttons appropriately
        elseif event.setting == "fp_view_belts_or_lanes" or
          event.setting == "fp_line_comments" or
          event.setting == "fp_ingredient_satisfaction" or
          event.setting == "fp_round_button_numbers" or
          event.setting == "fp_indicate_rounding" then
            refresh_production_pane(player)

        end
    end
end)

-- Refreshes the main dialog including it's dimensions
script.on_event(defines.events.on_player_display_resolution_changed, function(event)
    refresh_main_dialog(game.get_player(event.player_index), true)
end)

-- Refreshes the main dialog including it's dimensions
script.on_event(defines.events.on_player_display_scale_changed, function(event)
    refresh_main_dialog(game.get_player(event.player_index), true)
end)


-- Fires on pressing the 'Open/Close' keyboard shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.get_player(event.player_index)
    toggle_main_dialog(player)
end)

-- Fires on pressing of the keyboard shortcut to go up a floor
script.on_event("fp_floor_up", function(event)
    local player = game.get_player(event.player_index)
    if is_main_dialog_in_focus(player) then handle_floor_change_click(player, "up") end
end)

-- Fires on pressing of the keyboard shortcut to refresh the production table
script.on_event("fp_refresh_production", function(event)
    local player = game.get_player(event.player_index)
    if is_main_dialog_in_focus(player) then calculation.update(player, get_context(player).subfactory, true) end
end)

-- Fires on pressing the keyboard shortcut to cycle production views
script.on_event("fp_cycle_production_views", function(event)
    local player = game.get_player(event.player_index)
    if is_main_dialog_in_focus(player) then change_view_state(player, nil) end
end)

-- Fires on pressing of the keyboard shortcut to confirm a dialog
script.on_event("fp_confirm_dialog", function(event)
    local player = game.get_player(event.player_index)
    exit_modal_dialog(player, "submit", {})
end)


-- Fires on the activation of any quickbar lua shortcut
script.on_event(defines.events.on_lua_shortcut, function(event)
    local player = game.players[event.player_index]

    if event.prototype_name == "fp_open_interface" then
        toggle_main_dialog(player)
    end
end)

-- Fires when the user makes a selection using a selection-tool
script.on_event(defines.events.on_player_selected_area, function(event)
    local player = game.get_player(event.player_index)

    if event.item == "fp_beacon_selector" then
        leave_beacon_selection(player, table_size(event.entities))
    end
end)

-- Fires when the item that the player is holding changes
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    -- If the cursor stack is not valid_for_read, it's empty, thus the selector has been put away
    if get_ui_state(player).selection_mode and not player.cursor_stack.valid_for_read then
        leave_beacon_selection(player, nil)
    end
end)


-- Fires the user action of closing a dialog
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    local ui_state = get_ui_state(player)

	if event.gui_type == defines.gui_type.custom and event.element and event.element.visible
      and string.find(event.element.name, "^fp_.+$") then

        -- Close or hide any modal dialog or leave selection mode
        if string.find(event.element.name, "^fp_frame_modal_dialog[a-z_]*$") then
            if ui_state.selection_mode then leave_beacon_selection(player, nil)
            else exit_modal_dialog(player, "cancel", {}) end
    
        -- Toggle the main dialog
        elseif event.element.name == "fp_frame_main_dialog" then
            toggle_main_dialog(player)
            
        end
	end
end)

-- Fires on any radiobutton change
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)

    -- Toggles the selected preference
    if string.find(event.element.name, "^fp_checkbox_preferences_[a-z_]+$") then
        local preference = string.gsub(event.element.name, "fp_checkbox_preferences_", "")
        get_preferences(player)[preference] = event.element.state

    end
end)

-- Fires on any radiobutton change
script.on_event(defines.events.on_gui_switch_state_changed, function(event)
    local player = game.get_player(event.player_index)

    -- Changes the tutorial-mode preference
    if event.element.name == "fp_switch_tutorial_mode" then
        local state = ui_util.switch.convert_to_boolean(event.element.switch_state)
        get_preferences(player).tutorial_mode = state

    -- Applies the disabled/hidden filter to a picker dialog
    elseif string.find(event.element.name, "^fp_switch_picker_filter_condition_[a-z]+$") then
        local filter_name = string.gsub(event.element.name, "fp_switch_picker_filter_condition_", "")
        handle_filter_switch_flick(player, filter_name, event.element.switch_state)

    end
end)

-- Fires on any changes to a textbox/-field
script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = game.get_player(event.player_index)
    
    -- Persists (assembly) line percentage changes
    if string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
        handle_percentage_change(player, event.element)

    -- Persists (assembly) line comment changes
    elseif string.find(event.element.name, "^fp_textfield_line_comment_%d+$") then
        handle_comment_change(player, event.element)
        
    -- Activates the instant filter based on user search-string entry
    elseif event.element.name == "fp_textfield_picker_search_bar" and
      not get_settings(player).performance_mode then
        picker.search(player)

    -- Persists mining productivity changes
    elseif event.element.name == "fp_textfield_mining_prod" then
        handle_mining_prod_change(player, event.element)

    -- Limits the subfactory name length (implemented here for better responsiveness)
    elseif event.element.name == "fp_textfield_subfactory_name" then
        event.element.text = string.sub(event.element.text, 1, 24)

    end
end)

-- Fires on any confirmation of a textfield
script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = game.get_player(event.player_index)
    
    -- Re-run calculations when the mining prod changes, or cancel custom mining prod 'mode'
    if event.element.name == "fp_textfield_mining_prod" then
        handle_mining_prod_confirmation(player)

    -- Re-run calculations when a line percentage change is confirmed
    elseif string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
        handle_percentage_confirmation(player, event.element)

    -- Runs the picker search
    elseif event.element.name == "fp_textfield_picker_search_bar" then
        picker.search(player)
        event.element.focus()

    -- Submit any modal dialog, if it is open
    elseif get_ui_state(player).modal_dialog_type ~= nil then
        exit_modal_dialog(player, "submit", {})

    end
end)

-- Fires on any click on a GUI element
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    local ui_state = get_ui_state(player)
    
    -- Determine click type and direction
    local click, direction, action

    if event.button == defines.mouse_button_type.left then click = "left"
    elseif event.button == defines.mouse_button_type.right then click = "right" end

    if click == "left" then
        if not event.control and event.shift then direction = "positive" 
        elseif event.control and not event.shift then direction = "negative" end
    elseif click == "right" then
        if event.control and not event.shift and not event.alt then action = "delete"
        elseif not event.control and not event.shift and not event.alt then action = "edit" end
    end

    -- Handle the actual click
    if string.find(event.element.name, "^fp_.+$") then
        -- Redo the calculations if selecting a percentage textfield so at least something makes some fucking sense
        -- I can't even do this, this is terrible
        --[[ if event.element.type == "textfield" and string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
            local line_id = string.gsub(event.element.name, "fp_textfield_line_percentage_", "")
            local scroll_pane = event.element.parent.parent
            calculation.update(player, ui_state.context.subfactory, true)
            scroll_pane["table_production_pane"]["fp_textfield_line_percentage_" .. line_id].focus() ]]


        -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
        if event.element.name == "fp_button_toggle_interface" 
          or event.element.name == "fp_button_titlebar_exit" then
            toggle_main_dialog(player)

        -- Opens the tutorial dialog
        elseif event.element.name == "fp_button_titlebar_tutorial" then
            enter_modal_dialog(player, {type="tutorial", close=true})

        -- Opens the tutorial dialog
        elseif event.element.name == "fp_button_tutorial_add_example" then
            handle_add_example_subfactory_click(player)

        -- Opens the preferences dialog
        elseif event.element.name == "fp_button_titlebar_preferences" then
            enter_modal_dialog(player, {type="preferences", close=true})
        
        -- Opens the new-subfactory dialog
        elseif event.element.name == "fp_button_new_subfactory" then
            enter_modal_dialog(player, {type="subfactory", submit=true})

        -- Opens the edit-subfactory dialog
        elseif event.element.name == "fp_button_edit_subfactory" then
            local subfactory = ui_state.context.subfactory
            enter_modal_dialog(player, {type="subfactory", object=subfactory, submit=true, delete=true})

        -- Reacts to the archive button being pressed
        elseif event.element.name == "fp_button_archive_subfactory" then
            handle_subfactory_archivation(player)

        -- Reacts to the delete button being pressed
        elseif event.element.name == "fp_button_delete_subfactory" then
            handle_subfactory_deletion(player)

        -- Toggles the archive-view-mode
        elseif event.element.name == "fp_button_toggle_archive" then
            toggle_archive_view(player)
            
        -- Opens notes dialog
        elseif event.element.name == "fp_button_view_notes" then
            enter_modal_dialog(player, {type="notes", submit=true})

        -- Changes into the manual override of the mining prod mode
        elseif event.element.name == "fp_button_mining_prod_override" then
            mining_prod_override(player)

        -- Opens the add-product dialog
        elseif event.element.name == "fp_sprite-button_add_product" then
            enter_modal_dialog(player, {type="item_picker", submit=true})
        
        -- Toggles the TopLevelItems-amount display state
        elseif event.element.name == "fp_button_item_amount_toggle" then
            toggle_floor_total_display(player, event.element)

        -- Refreshes the production table
        elseif event.element.name == "fp_sprite-button_refresh_production" then
            calculation.update(player, ui_state.context.subfactory, true)

        -- Clears all the comments on the current floor
        elseif event.element.name == "fp_button_production_clear_comments" then
            clear_recipe_comments(player)

        -- Repairs the current subfactory as well as possible
        elseif event.element.name == "fp_button_error_bar_repair" then
            handle_subfactory_repair(player)

        -- Maxes the amount of modules on a modules-dialog
        elseif event.element.name == "fp_button_max_modules" then
            max_module_amount(player)

        -- Gives the player the beacon-selector
        elseif event.element.name == "fp_button_beacon_selector" then
            enter_beacon_selection(player)

        -- Reacts to a modal dialog button being pressed
        elseif string.find(event.element.name, "^fp_button_modal_dialog_[a-z]+$") then
            local action = string.gsub(event.element.name, "fp_button_modal_dialog_", "")
            exit_modal_dialog(player, action, {})
        
        -- Reacts to a subfactory button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_subfactory_%d+$") then
            local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_element_click(player, subfactory_id, click, direction, action)
            
        -- Changes the timescale of the current subfactory
        elseif string.find(event.element.name, "^fp_button_timescale_%d+$") then
            local timescale = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_timescale_change(player, timescale)
            
        -- Reacts to any subfactory_pane item button being pressed (class name being a string is fine)
        elseif string.find(event.element.name, "^fp_sprite%-button_subpane_[a-zA-Z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            _G["handle_" .. split_string[4] .. "_element_click"](player, split_string[5], click, direction, action, event.alt)

        -- Reacts to a item group button being pressed (item or recipe group)
        elseif string.find(event.element.name, "^fp_sprite%-button_[a-z]+_group_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            picker.select_item_group(player, split_string[3], split_string[5])

        -- Reacts to a picker object button being pressed (the variable can me one or more ids)
        elseif string.find(event.element.name, "^fp_sprite%-button_picker_[a-z]+_object_[0-9_]+$") then
            local split_string = ui_util.split(event.element.name, "_")
            _G["handle_picker_" .. split_string[4] .. "_click"](player, event.element)

        -- Reacts to a chooser element button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_chooser_element_[0-9_]+$") then
            local element_id = string.gsub(event.element.name, "fp_sprite%-button_chooser_element_", "")
            handle_chooser_element_click(player, element_id)

        -- Reacts to a floor-changing button being pressed (up/top)
        elseif string.find(event.element.name, "^fp_button_floor_[a-z]+$") then
            local destination = string.gsub(event.element.name, "fp_button_floor_", "")
            handle_floor_change_click(player, destination)

        -- Reacts to a change of the production pane view
        elseif string.find(event.element.name, "^fp_button_production_titlebar_view_[a-zA-Z-_]+$") then
            local view_name = string.gsub(event.element.name, "fp_button_production_titlebar_view_", "")
            change_view_state(player, view_name)

        -- Reacts to the recipe button on an (assembly) line being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_line_recipe_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_line_recipe_click(player, line_id, click, direction, action, event.alt)

        -- Reacts to the machine button on an (assembly) line being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_line_machine_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_machine_change(player, line_id, nil, click, direction)
            
        -- Changes the machine of the selected (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_machine_%d+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_machine_change(player, split_string[5], split_string[6], click, direction)

        -- Handles click on the add-module-button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_add_module_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_line_module_click(player, line_id, nil, click, direction, nil)

        -- Handles click on any module button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_module_%d+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_line_module_click(player, split_string[5], split_string[6], click, direction, action, event.alt)

        -- Handles click on the add-beacon-button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_add_beacon_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_line_beacon_click(player, line_id, nil, click, direction, nil)
        
        -- Handles click on any beacon (module or beacon) button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_beacon_[a-z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_line_beacon_click(player, split_string[6], split_string[5], click, direction, action, event.alt)

        -- Handles click on any module/beacon button on a modules/beacons modal dialog
        elseif string.find(event.element.name, "^fp_sprite%-button_[a-z]+_selection_%d+_?%d*$") then
            handle_module_beacon_picker_click(player, event.element)

        -- Reacts to any 1d-prototype preference button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_[a-z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_preferences_change(player, split_string[4], split_string[5])

        -- Reacts to any preferences machine button being pressed (special case of a 2d-prototype preference)
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_machine_%d+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_preferences_machine_change(player, split_string[5], split_string[6])

        -- Reacts to any (assembly) line item button being pressed (strings for class names are fine)
        elseif string.find(event.element.name, "^fp_sprite%-button_line_%d+_[a-zA-Z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_item_button_click(player, split_string[4], split_string[5], split_string[6], click, direction, event.alt)
        
        end

        -- Only reset hint if one of this mod's actual controls is pressed
        ui_util.message.refresh(player)
    end
end)
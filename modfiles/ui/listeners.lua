require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")
require("ui.util")

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

        -- Changes the width of the main dialog
        elseif event.setting == "fp_subfactory_items_per_row" or
          event.setting == "fp_floor_recipes_at_once" then
            refresh_main_dialog(player, true)

        -- Refreshes the view selection or recipe machine buttons appropriately
        elseif event.setting == "fp_view_belts_or_lanes" or
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


script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.get_player(event.player_index)
    toggle_main_dialog(player)
end)

script.on_event("fp_floor_up", function(event)
    local player = game.get_player(event.player_index)
    if ui_util.rate_limiting_active(player, event.input_name, event.input_name) then return end
    if is_main_dialog_in_focus(player) then handle_floor_change_click(player, "up") end
end)

script.on_event("fp_refresh_production", function(event)
    local player = game.get_player(event.player_index)
    if is_main_dialog_in_focus(player) then calculation.update(player, get_context(player).subfactory, true) end
end)

script.on_event("fp_cycle_production_views", function(event)
    local player = game.get_player(event.player_index)
    if is_main_dialog_in_focus(player) then change_view_state(player, nil) end
end)

script.on_event("fp_confirm_dialog", function(event)
    local player = game.get_player(event.player_index)
    if ui_util.rate_limiting_active(player, event.input_name, event.input_name) then return end
    exit_modal_dialog(player, "submit", {})
end)

script.on_event("fp_focus_searchfield", function(event)
    local player = game.get_player(event.player_index)
    if get_ui_state(player).modal_dialog_type == "product" then
        ui_util.find_modal_dialog(player)["flow_modal_dialog"]["flow_item_picker"]
          ["table_search_bar"]["fp_textfield_item_picker_search_bar"].focus()
    end
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

    if event.item == "fp_beacon_selector" and get_flags(player).selection_mode then
        if ui_util.rate_limiting_active(player, event.name, event.item) then return end
        leave_beacon_selection(player, table_size(event.entities))
    end
end)

-- Fires when the item that the player is holding changes
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    -- If the cursor stack is not valid_for_read, it's empty, thus the selector has been put away
    if get_flags(player).selection_mode and not player.cursor_stack.valid_for_read then
        leave_beacon_selection(player, nil)
    end
end)


-- Fires the user action of closing a dialog
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)

	if event.gui_type == defines.gui_type.custom and event.element and event.element.visible
      and string.find(event.element.name, "^fp_.+$") then
        -- Close or hide any modal dialog or leave selection mode
        if string.find(event.element.name, "^fp_frame_modal_dialog[a-z_]*$") then
            if get_flags(player).selection_mode then leave_beacon_selection(player, nil)
            else exit_modal_dialog(player, "cancel", {}) end
    
        -- Toggle the main dialog
        elseif event.element.name == "fp_frame_main_dialog" then
            toggle_main_dialog(player)
            
        end
	end
end)

-- Fires on any confirmation of a textfield
script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name
    
    -- Re-run calculations when the mining prod changes, or cancel custom mining prod 'mode'
    if element_name == "fp_textfield_mining_prod" then
        handle_mining_prod_confirmation(player)

    -- Re-run calculations when a line percentage change is confirmed
    elseif string.find(element_name, "^fp_textfield_line_percentage_%d+$") then
        handle_percentage_confirmation(player, event.element)

    -- Submit any modal dialog, if it is open
    elseif get_ui_state(player).modal_dialog_type ~= nil then
        if ui_util.rate_limiting_active(player, "submit_modal_dialog", element_name) then return end
        exit_modal_dialog(player, "submit", {})

    end
end)


-- Fires on any radiobutton change
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    -- Toggles the selected general preference
    if string.find(element_name, "^fp_checkbox_preferences_[a-z_]+$") then
        handle_general_preference_change(player, event.element)

    -- Toggles the selected production preference
    elseif string.find(element_name, "^fp_checkbox_production_preferences_[a-z_]+$") then
        handle_production_preference_change(player, event.element)

    end
end)

-- Fires on any switch change
script.on_event(defines.events.on_gui_switch_state_changed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    -- Changes the tutorial-mode preference
    if element_name == "fp_switch_tutorial_mode" then
        local new_state = ui_util.switch.convert_to_boolean(event.element.switch_state)
        handle_tutorial_mode_change(player, new_state)

    -- Applies the disabled/hidden filter to the recipe dialog
    elseif string.find(element_name, "^fp_switch_recipe_filter_[a-z]+$") then
        local filter_name = string.gsub(element_name, "fp_switch_recipe_filter_", "")
        handle_recipe_filter_switch_flick(player, filter_name, event.element.switch_state)

    -- Refreshes the data attached to the clicked scope-switch
    elseif string.find(element_name, "^fp_switch_utility_scope_[a-z]+$") then
        local scope_type = string.gsub(element_name, "fp_switch_utility_scope_", "")
        handle_utility_scope_change(player, scope_type, event.element.switch_state)
    
    end
end)

-- Fires on any changes to a textbox/-field
script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    -- Only handle my actual events
    if string.find(element_name, "^fp_.+$") then
        -- Activates the instant filter based on user search-string entry
        if element_name == "fp_textfield_item_picker_search_bar" then
            if ui_util.rate_limiting_active(player, "filter_item_picker", element_name) then
                -- Create/update the nth_tick handler only when rate limiting is active
                ui_util.set_nth_tick_refresh(player, event.element)
                return
            end

            item_picker.handle_searchfield_change(event.element)

        -- Persists notes changes
        elseif element_name == "fp_text-box_notes" then
            handle_notes_change(player, event.element)

        -- Persists mining productivity changes
        elseif element_name == "fp_textfield_mining_prod" then
            handle_mining_prod_change(player, event.element)

        -- Persists (assembly) line percentage changes
        elseif string.find(element_name, "^fp_textfield_line_percentage_%d+$") then
            handle_percentage_change(player, event.element)

        -- Persists (assembly) line comment changes
        elseif string.find(element_name, "^fp_textfield_line_comment_%d+$") then
            handle_comment_change(player, event.element)
            
        end
    end
end)

-- Fires on any dropdown and listbox change
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local player = game.get_player(event.player_index)

    -- Changes the current alt_action
    if event.element.name == "fp_drop_down_alt_action" then
        local selected_index = event.element.selected_index
        handle_alt_action_change(player, selected_index)
    end
end)


-- Fires on any click on a GUI element
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    local ui_state = get_ui_state(player)
    local element_name = event.element.name
    
    -- Only handle my actual events
    if string.find(element_name, "^fp_.+$") then
        -- Incorporate rate limiting
        if ui_util.rate_limiting_active(player, event.name, element_name) then return end

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

        -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
        if element_name == "fp_button_toggle_interface" 
          or element_name == "fp_button_titlebar_exit" then
            toggle_main_dialog(player)

        -- Opens the tutorial dialog
        elseif element_name == "fp_button_titlebar_tutorial" then
            enter_modal_dialog(player, {type="tutorial", close=true})

        -- Opens the tutorial dialog
        elseif element_name == "fp_button_tutorial_add_example" then
            handle_add_example_subfactory_click(player)

        -- Opens the preferences dialog
        elseif element_name == "fp_button_titlebar_preferences" then
            enter_modal_dialog(player, {type="preferences", close=true})
        
        -- Opens the new-subfactory dialog
        elseif element_name == "fp_button_new_subfactory" then
            enter_modal_dialog(player, {type="subfactory", submit=true})

        -- Opens the edit-subfactory dialog
        elseif element_name == "fp_button_edit_subfactory" then
            local subfactory = ui_state.context.subfactory
            enter_modal_dialog(player, {type="subfactory", submit=true,
              delete=true, modal_data={subfactory=subfactory}})

        -- Reacts to the archive button being pressed
        elseif element_name == "fp_button_archive_subfactory" then
            handle_subfactory_archivation(player)

        -- Reacts to the delete button being pressed
        elseif element_name == "fp_button_delete_subfactory" then
            handle_subfactory_deletion(player)

        -- Toggles the archive-view-mode
        elseif element_name == "fp_button_toggle_archive" then
            toggle_archive_view(player)
            
        -- Opens utilitys dialog
        elseif element_name == "fp_button_open_utility_dialog" then
            enter_modal_dialog(player, {type="utility"})

        -- Changes into the manual override of the mining prod mode
        elseif element_name == "fp_button_mining_prod_override" then
            mining_prod_override(player)

        -- Opens the add-product dialog
        elseif element_name == "fp_sprite-button_add_product" then
            enter_modal_dialog(player, {type="product", submit=true})
        
        -- Toggles the TopLevelItems-amount display state
        elseif element_name == "fp_button_item_amount_toggle" then
            toggle_floor_total_display(player, event.element)

        -- Refreshes the production table
        elseif element_name == "fp_sprite-button_refresh_production" then
            calculation.update(player, ui_state.context.subfactory, true)

        -- Clears all the comments on the current floor
        elseif element_name == "fp_button_production_clear_comments" then
            clear_recipe_comments(player)

        -- Repairs the current subfactory as well as possible
        elseif element_name == "fp_button_error_bar_repair" then
            handle_subfactory_repair(player)

        -- Maxes the amount of modules on a modules-dialog
        elseif element_name == "fp_button_max_modules" then
            max_module_amount(player)

        -- Gives the player the beacon-selector
        elseif element_name == "fp_button_beacon_selector" then
            enter_beacon_selection(player)

        -- Reacts to a modal dialog button being pressed
        elseif string.find(element_name, "^fp_button_modal_dialog_[a-z]+$") then
            local action = string.gsub(element_name, "fp_button_modal_dialog_", "")
            exit_modal_dialog(player, action, {})
        
        -- Reacts to a subfactory button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_subfactory_%d+$") then
            local subfactory_id = tonumber(string.match(element_name, "%d+"))
            handle_subfactory_element_click(player, subfactory_id, click, direction, action)
            
        -- Changes the timescale of the current subfactory
        elseif string.find(element_name, "^fp_button_timescale_%d+$") then
            local timescale = tonumber(string.match(element_name, "%d+"))
            handle_subfactory_timescale_change(player, timescale)
            
        -- Reacts to any subfactory_pane item button being pressed (class name being a string is fine)
        elseif string.find(element_name, "^fp_sprite%-button_subpane_[a-zA-Z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            _G["handle_" .. split_string[4] .. "_element_click"](player, split_string[5], click, direction, action, event.alt)

        -- Reacts to an item group button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_item_group_%d+$") then
            local picker_flow = event.element.parent.parent.parent
            local group_id = string.match(element_name, "%d+")
            item_picker.select_group(picker_flow, group_id)

        -- Reacts to an item picker button being pressed
        elseif string.find(element_name, "^fp_button_item_pick_%d+_%d+$") then
            local item_identifier = string.gsub(element_name, "fp_button_item_pick_", "")
            _G["handle_item_picker_" .. ui_state.modal_dialog_type .. "_click"](player, item_identifier)

        -- Reacts to a recipe picker button being pressed
        elseif string.find(element_name, "^fp_button_recipe_pick_[0-9]+$") then
            local recipe_id = tonumber(string.match(element_name, "%d+"))
            attempt_adding_recipe_line(player, recipe_id)

        -- Reacts to a chooser element button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_chooser_element_[0-9_]+$") then
            local element_id = string.gsub(element_name, "fp_sprite%-button_chooser_element_", "")
            handle_chooser_element_click(player, element_id, direction, event.alt)

        -- Reacts to a floor-changing button being pressed (up/top)
        elseif string.find(element_name, "^fp_button_floor_[a-z]+$") then
            local destination = string.gsub(element_name, "fp_button_floor_", "")
            handle_floor_change_click(player, destination)

        -- Reacts to a change of the production pane view
        elseif string.find(element_name, "^fp_button_production_titlebar_view_[a-zA-Z-_]+$") then
            local view_name = string.gsub(element_name, "fp_button_production_titlebar_view_", "")
            change_view_state(player, view_name)

        -- Reacts to the recipe button on an (assembly) line being pressed
        elseif string.find(element_name, "^fp_sprite%-button_line_recipe_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            handle_line_recipe_click(player, line_id, click, direction, action, event.alt)

        -- Reacts to the machine button on an (assembly) line being pressed
        elseif string.find(element_name, "^fp_sprite%-button_line_machine_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            handle_machine_change(player, line_id, nil, click, direction, event.alt)
            
        -- Changes the machine of the selected (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_machine_%d+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_machine_change(player, split_string[5], split_string[6], click, direction)

        -- Handles click on the add-module-button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_add_module_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            handle_line_module_click(player, line_id, nil, click, direction, nil)

        -- Handles click on any module button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_module_%d+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_line_module_click(player, split_string[5], split_string[6], click, direction, action, event.alt)

        -- Handles click on the add-beacon-button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_add_beacon_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            handle_line_beacon_click(player, line_id, nil, click, direction, nil)
        
        -- Handles click on any beacon (module or beacon) button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_beacon_[a-z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_line_beacon_click(player, split_string[6], split_string[5], click, direction, action, event.alt)

        -- Handles click on any module/beacon button on a modules/beacons modal dialog
        elseif string.find(element_name, "^fp_sprite%-button_[a-z]+_selection_%d+_?%d*$") then
            handle_module_beacon_picker_click(player, event.element)

        -- Reacts to any 1d-prototype preference button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_preferences_[a-z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_preferences_change(player, split_string[4], split_string[5])

        -- Reacts to any preferences machine button being pressed (special case of a 2d-prototype preference)
        elseif string.find(element_name, "^fp_sprite%-button_preferences_machine_%d+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_preferences_machine_change(player, split_string[5], split_string[6])

        -- Reacts to any (assembly) line item button being pressed (strings for class names are fine)
        elseif string.find(element_name, "^fp_sprite%-button_line_%d+_[a-zA-Z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            handle_item_button_click(player, split_string[4], split_string[5], split_string[6], click, direction, event.alt)
        
        end
    end
end)
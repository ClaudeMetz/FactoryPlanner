require("ui.util")
require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")

-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    -- This mod doesn't use runtime-global settings, so that case can be ignored
    -- (runtime-global changes don't have a player attached, so this would crash otherwise)
    if event.setting_type ~= "runtime-global" then
        local player = game.get_player(event.player_index)

        -- Reload all user mod settings
        reload_settings(player)

        -- Toggles the visibility of the toggle-main-dialog-button
        if event.setting == "fp_display_gui_button" then 
            toggle_button_interface(player)

        -- Changes the width of the main dialog. so it needs to be refreshed
        elseif event.setting == "fp_subfactory_items_per_row" or
          event.setting == "fp_floor_recipes_at_once" then
            refresh_main_dialog(player, true)

        -- Refreshes the view selection or recipe machine buttons appropriately
        elseif event.setting == "fp_view_belts_or_lanes" or event.setting == "fp_indicate_rounding" then
            refresh_production_pane(player)

        end
    end
end)


-- Fires on pressing the 'Open/Close' keyboard shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.get_player(event.player_index)
    toggle_main_dialog(player)
end)

-- Fires on pressing the keyboard shortcut to cycle production views
script.on_event("fp_cycle_production_views", function(event)
    local player = game.get_player(event.player_index)
    change_view_state(player, nil)
end)

-- Fires on pressing of the keyboard shortcut to confirm a dialog
script.on_event("fp_confirm_dialog", function(event)
    local player = game.get_player(event.player_index)
    exit_modal_dialog(player, "submit", {})
end)


-- Fires the user action of closing a dialog
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)

	if event.gui_type == defines.gui_type.custom and event.element and event.element.visible
      and string.find(event.element.name, "^fp_.+$") then

        -- Close or hide any modal dialog
		if string.find(event.element.name, "^fp_frame_modal_dialog[a-z_]*$") then
			exit_modal_dialog(player, "cancel", {})
    
        -- Toggle the main dialog
		elseif event.element.name == "fp_frame_main_dialog" then
            toggle_main_dialog(player)
            
        end
	end
end)

-- Fires on any radiobutton change
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)

    -- Changes the tutorial-mode preference
    if event.element.name == "fp_checkbox_tutorial_mode" then
        get_preferences(player).tutorial_mode = event.element.state

    -- Applies the disabled/hidden filter to a picker dialog
    elseif string.find(event.element.name, "^fp_checkbox_picker_filter_condition_[a-z]+$") then
        local filter = string.gsub(event.element.name, "fp_checkbox_preferences_", "")
        handle_filter_radiobutton_click(player, filter, event.element.state)

    -- Toggles the selected preference
    elseif string.find(event.element.name, "^fp_checkbox_preferences_[a-z_]+$") then
        local preference = string.gsub(event.element.name, "fp_checkbox_preferences_", "")
        get_preferences(player)[preference] = event.element.state

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
        
    -- Actives the instant filter based on user serachfield text entry
    elseif event.element.name == "fp_textfield_picker_search_bar" then
        picker.search(player)

    -- Persists mining productivity changes
    elseif event.element.name == "fp_textfield_mining_prod" then
        handle_mining_prod_change(player, event.element)

    elseif event.element.name == "fp_textfield_subfactory_name" then
        handle_subfactory_name_change(player, event.element)

    end
end)

-- Fires on any confirmation of a textfield
script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = game.get_player(event.player_index)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    
    -- Re-run calculations when the mining prod changes, or cancel custom mining prod 'mode'
    if event.element.name == "fp_textfield_mining_prod" then
        if subfactory.mining_productivity == nil then ui_state.current_activity = nil end
        update_calculations(player, subfactory)

    -- Re-run calculations when a line percentage changes
    elseif string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
        update_calculations(player, subfactory)

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
    local click, direction = nil, nil

    if event.button == defines.mouse_button_type.left then click = "left"
    elseif event.button == defines.mouse_button_type.right then click = "right" end

    if click == "left" then
        if not event.control and event.shift then direction = "positive" 
        elseif event.control and not event.shift then direction = "negative" end
    end

    -- Handle the actual click
    if string.find(event.element.name, "^fp_.+$") then
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

        -- Reacts to the delete button being pressed
        elseif event.element.name == "fp_button_delete_subfactory" then
            handle_subfactory_deletion(player)
            
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

        -- Clears all the comments on the current floor
        elseif event.element.name == "fp_button_production_clear_comments" then
            clear_recipe_comments(player)

        -- Repairs the current subfactory as well as possible
        elseif event.element.name == "fp_button_error_bar_repair" then
            handle_subfactory_repair(player)

        -- Maxes the amount of modules on a modules-dialog
        elseif event.element.name == "fp_button_max_modules" then
            max_module_amount(player)

        -- Reacts to a modal dialog button being pressed
        elseif string.find(event.element.name, "^fp_button_modal_dialog_[a-z]+$") then
            local action = string.gsub(event.element.name, "fp_button_modal_dialog_", "")
            exit_modal_dialog(player, action, {})
        
        -- Reacts to a subfactory button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_subfactory_%d+$") then
            local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_element_click(player, subfactory_id, click, direction)
            
        -- Changes the timescale of the current subfactory
        elseif string.find(event.element.name, "^fp_button_timescale_%d+$") then
            local timescale = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_timescale_change(player, timescale)
            
        -- Reacts to any subfactory_pane item button being pressed (class name being a string is fine)
        elseif string.find(event.element.name, "^fp_sprite%-button_subpane_[a-zA-Z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            _G["handle_" .. split_string[4] .. "_element_click"](player, split_string[5], click, direction, event.alt)

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
            local element_name = string.gsub(event.element.name, "fp_sprite%-button_chooser_element_", "")
            handle_chooser_element_click(player, element_name)

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
            handle_line_recipe_click(player, line_id, click, direction, event.alt)

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
            handle_line_module_click(player, split_string[5], split_string[6], click, direction, event.alt)

        -- Handles click on the add-beacon-button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_add_beacon_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_line_beacon_click(player, line_id, nil, click, direction, nil)
        
        -- Handles click on any beacon (module or beacon) button on an (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_beacon_[a-z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_line_beacon_click(player, split_string[6], split_string[5], click, direction, event.alt)

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
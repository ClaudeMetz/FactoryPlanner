require("ui.util")
require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")

-- Session variable to deselect previous text as Factorio doesn't do this (yet)
-- (Used in production_pane.handle_percentage_textfield_click())
local previously_selected_textfield = nil

-- Sets up global data structure of the mod
script.on_init(function()
    global_init()
end)

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
script.on_configuration_changed(function()
    handle_configuration_change()
end)

-- Creates some lua-global tables for convenience and performance
script.on_load(function()
    item_recipe_map = generator.item_recipe_map()
    item_groups = generator.item_groups()
end)

-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)

    -- Sets up the player_table for the new player
    update_player_table(player, global)

    -- Sets up the GUI for the new player
    player_gui_init(player)

    -- Runs setup if developer mode is active
    data_util.run_dev_config(player)
end)

-- Fires when a player is irreversibly removed from a game
script.on_event(defines.events.on_player_removed, function(event)
    -- Removes the player from the global table
    global.players[event.player_index] = nil
end)


-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
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
end)


-- Fires on pressing of the 'Open/Close' keyboard shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.get_player(event.player_index)
    toggle_main_dialog(player)
end)

-- Fires on pressing of the keyboard shortcut to cycle production views
script.on_event("fp_cycle_production_views", function(event)
    local player = game.get_player(event.player_index)
    change_view_state(player, nil)
    refresh_main_dialog(player)
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

    -- Applies the disabled filter to a picker dialog
    if event.element.name == "fp_checkbox_picker_filter_condition_disabled" then
        handle_filter_radiobutton_click(player, "disabled", event.element.state)

    -- Applies the hidden filter to a picker dialog
    elseif event.element.name == "fp_checkbox_picker_filter_condition_hidden" then
        handle_filter_radiobutton_click(player, "hidden", event.element.state)
    
    -- Changes the preference to ignore barreling
    elseif event.element.name == "fp_checkbox_preferences_ignore_barreling" then
        get_preferences(player).ignore_barreling_recipes = event.element.state

    -- Changes the preference to show line comments
    elseif event.element.name == "fp_checkbox_preferences_enable_recipe_comments" then
        get_preferences(player).enable_recipe_comments = event.element.state

    end
end)

-- Fires on any changes to a textbox
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

    if click == "left" and not event.alt then
        if not event.control and event.shift then direction = "positive" 
        elseif event.control and not event.shift then direction = "negative" end
    end

    -- Determine object type (not always relevant, but useful in some places)
    local object_type = (ui_state.modal_dialog_type ~= nil) and 
      string.gsub(ui_state.modal_dialog_type, "_picker", "") or nil

    -- Handle the actual click
    if string.find(event.element.name, "^fp_.+$") then
        -- Handle clicks on textfields to improve user experience
        if string.find(event.element.name, "^fp_textfield_[a-z0-9_]+$") then
            -- Replaces the previously selected textfields text in case it is invalid (for percentage textfields)
            -- (also unselects it, which the base game does not yet do)
            if previously_selected_textfield ~= nil and previously_selected_textfield.valid
              and previously_selected_textfield.index ~= event.element.index then
                -- A reset is only needed on percentage textfields
                if string.find(previously_selected_textfield.name, "^fp_textfield_line_percentage_%d+$") then
                    local line_id = tonumber(string.match(previously_selected_textfield.name, "%d+"))
                    local line = Floor.get(get_context(player).floor, "Line", line_id)
                    previously_selected_textfield.text = line.percentage
                end
            end

            previously_selected_textfield = event.element
        end

        -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
        if event.element.name == "fp_button_toggle_interface" 
          or event.element.name == "fp_button_titlebar_exit" then
            toggle_main_dialog(player)

        -- Closes the modal dialog straight away
        elseif event.element.name == "fp_button_modal_dialog_cancel" then
            exit_modal_dialog(player, "cancel", {})

        -- Closes the modal dialog, calling the appropriate deletion function
        elseif event.element.name == "fp_button_modal_dialog_delete" then
            exit_modal_dialog(player, "delete", {})

        -- Submits the modal dialog, forwarding to the appropriate function
        elseif event.element.name == "fp_button_modal_dialog_submit" then
            exit_modal_dialog(player, "submit", {})

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

        -- Enters mode to change the timescale of the current subfactory
        elseif event.element.name == "fp_button_change_timescale" then
            handle_subfactory_timescale_change(player, nil)

        -- Opens notes dialog
        elseif event.element.name == "fp_button_view_notes" then
            enter_modal_dialog(player, {type="notes", submit=true})

        -- Sets all machines of the current subfactory to the preferred ones
        elseif event.element.name == "fp_button_set_prefmachines_subfactory" then
            handle_set_prefmachines_click(player, "subfactory")

        -- Sets all machines of the current floor to the preferred ones
        elseif event.element.name == "fp_button_set_prefmachines_floor" then
            handle_set_prefmachines_click(player, "floor")

        -- Opens the add-product dialog
        elseif event.element.name == "fp_sprite-button_add_product" then
            enter_modal_dialog(player, {type="item_picker", preserve=true, submit=true})
        
        -- Sets the selected floor to be the parent of the currently selected one
        elseif event.element.name == "fp_button_floor_up" then
            handle_floor_change_click(player, "up")

        -- Sets the selected floor to be the top one
        elseif event.element.name == "fp_button_floor_top" then
            handle_floor_change_click(player, "top")

        -- Clears all the comments on the current floor
        elseif event.element.name == "fp_button_production_clear_comments" then
            clear_recipe_comments(player)

        -- Repairs the current subfactory as well as possible
        elseif event.element.name == "fp_button_error_bar_repair" then
            handle_subfactory_repair(player)

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

        -- Reacts to a item group button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_item_group_%d+$") then
            local item_group_id = tonumber(string.match(event.element.name, "%d+"))
            picker.select_item_group(player, object_type, item_group_id)

        -- Reacts to a picker object button being pressed (the variable can me one or more ids)
        elseif string.find(event.element.name, "^fp_sprite%-button_picker_object_[0-9_]+$") then
            _G["handle_picker_" .. object_type .. "_click"](player, event.element)

        -- Reacts to a chooser element button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_chooser_element_[0-9_]+$") then
            local element_name = string.gsub(event.element.name, "fp_sprite%-button_chooser_element_", "")
            handle_chooser_element_click(player, element_name)

        -- Reacts to a change of the production pane view
        elseif string.find(event.element.name, "^fp_button_production_titlebar_view_[a-zA-Z-_]+$") then
            local view_name = string.gsub(event.element.name, "fp_button_production_titlebar_view_", "")
            change_view_state(player, view_name)
            refresh_production_pane(player)

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

        -- Reacts to any preferences machine button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_machine_%d+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_preferences_machine_change(player, split_string[5], split_string[6])

        -- Reacts to any preferences belt button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_belt_%d+$") then
            local belt_id = tonumber(string.match(event.element.name, "%d+"))
            handle_preferences_belt_change(player, belt_id)

        -- Reacts to any preferences fuel button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_fuel_%d+$") then
            local fuel_id = tonumber(string.match(event.element.name, "%d+"))
            handle_preferences_fuel_change(player, fuel_id)

        -- Reacts to any (assembly) line item button being pressed (strings for class names are fine)
        elseif string.find(event.element.name, "^fp_sprite%-button_line_%d+_[a-zA-Z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_item_button_click(player, split_string[4], split_string[5], split_string[6], click, direction, event.alt)
        
        end

        -- Only reset hint if one of this mod's actual controls is pressed
        refresh_message(player)
    end
end)
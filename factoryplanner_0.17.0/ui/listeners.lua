-- Session variable to deselect previous text as Factorio doesn't do this (yet)
local previously_selected_textfield = nil

-- Sets up global data structure of the mod
script.on_init(function()
    global_init()
end)

-- Prompts a GUI and prototype reload and a validity check on all subfactories
script.on_configuration_changed(function()
    handle_configuration_change()
end)


-- Fires when a player loads into a game for the first time
script.on_event(defines.events.on_player_created, function(event)
    local player = game.players[event.player_index]

    -- Sets up a player in the global table for the new player
    player_init(player)

    -- Sets up the GUI for the new player
    player_gui_init(player)

    -- Runs setup if developer mode is active
    run_dev_config(player)
end)

-- Fires when a player is irreversibly removed from a game
script.on_event(defines.events.on_player_removed, function(event)
    local player = game.players[event.player_index]

    -- Removes the player from the global table
    player_remove(player)
end)


-- Fires when mods settings change to incorporate them
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    local player = game.players[event.player_index]

    -- Toggles the visibility of the toggle-main-dialog-button
    if event.setting == "fp_display_gui_button" then 
        toggle_button_interface(player)

    -- Changes the width of the main dialog by regenerating it
    elseif event.setting == "fp_subfactory_items_per_row" then
        global.players[player.index].items_per_row = tonumber(event.setting.value)
        refresh_main_dialog(player, true)
    end
end)


-- Sets the custom space science recipe to enabled when rockets are researched
script.on_event(defines.events.on_research_finished, function(event)
    if event.research.name == "space-science-pack" then
        global.all_recipes["fp-space-science-pack"].enabled = true
    end
end)


-- Fires on pressing of the custom 'Open/Close' shortcut
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.players[event.player_index]
    toggle_main_dialog(player)
end)


-- Fires the user action of closing a dialog
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.players[event.player_index]

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
    local player = game.players[event.player_index]

    if string.find(event.element.name, "^fp_checkbox_filter_condition_%l+$") then
        apply_recipe_filter(player)
    end
end)

-- Fires on any changes to a textbox
script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = game.players[event.player_index]
    local player_table = global.players[player.index]

    -- Persists (assembly) line percentage changes (No function call here for latency reasons)
    if string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
        local floor = player_table.context.floor
        local line = Floor.get(floor, "Line", tonumber(string.match(event.element.name, "%d+")))
        local new_string = event.element.text
        local new_percentage = tonumber(new_string)

        if new_percentage == nil or new_percentage < 0 then
            event.element.text = line.percentage
            queue_hint_message(player, {"label.error_invalid_percentage"})
        else
            line.percentage = new_percentage
            -- Update related datasets
            if line.subfloor then line.subfloor.Line[1].percentage = new_percentage
            elseif line.id == 1 and floor.origin_line then floor.origin_line.percentage = new_percentage end

            queue_hint_message(player, "")
            update_calculations(player, player_table.context.subfactory)
            refresh_production_table(player)
            
            player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]["scroll-pane_production_pane"]
              ["table_production_pane"]["fp_textfield_line_percentage_" .. line.id].focus()
        end
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
    local player_table = global.players[player.index]
    local found = true
    
    if string.find(event.element.name, "^fp_.+$") then  -- performance improvement

        -- Reacts to the toggle-main-dialog-button or the close-button on the main dialog being pressed
        if event.element.name == "fp_button_toggle_interface" or event.element.name == "fp_button_titlebar_exit"
            and is_left_click then
            toggle_main_dialog(player)

        -- Closes the modal dialog straight away
        elseif event.element.name == "fp_button_modal_dialog_cancel" and is_left_click then
            exit_modal_dialog(player, "cancel", {})

        -- Closes the modal dialog, calling the appropriate deletion function
        elseif event.element.name == "fp_button_modal_dialog_delete" and is_left_click then
            exit_modal_dialog(player, "delete", {})

        -- Submits the modal dialog, forwarding to the appropriate function
        elseif event.element.name == "fp_button_modal_dialog_submit" and is_left_click then
            exit_modal_dialog(player, "submit", {})

        -- Opens the preferences dialog
        elseif event.element.name == "fp_button_titlebar_preferences" and is_left_click then
            enter_modal_dialog(player, {type="preferences", close=true})
        
        -- Opens the new-subfactory dialog
        elseif event.element.name == "fp_button_new_subfactory" and is_left_click then
            enter_modal_dialog(player, {type="subfactory", submit=true})

        -- Opens the edit-subfactory dialog
        elseif event.element.name == "fp_button_edit_subfactory" and is_left_click then
            local subfactory = player_table.context.subfactory
            enter_modal_dialog(player, {type="subfactory", object=subfactory, submit=true, delete=true})

        -- Reacts to the delete button being pressed
        elseif event.element.name == "fp_button_delete_subfactory" and is_left_click then
            handle_subfactory_deletion(player)

        -- Enters mode to change the timescale of the current subfactory
        elseif event.element.name == "fp_button_change_timescale" and is_left_click then
            handle_subfactory_timescale_change(player, nil)

        -- Opens notes dialog
        elseif event.element.name == "fp_button_view_notes" and is_left_click then
            enter_modal_dialog(player, {type="notes", submit=true})

        -- Opens the add-product dialog
        elseif event.element.name == "fp_sprite-button_add_product" and is_left_click then
            enter_modal_dialog(player, {type="product", submit=true})

        -- Submits the entered search term in the recipe dialog
        elseif event.element.name == "fp_sprite-button_search_recipe" and is_left_click then
            apply_recipe_filter(player)

        -- Sets the selected floor to be the parent of the currently selected one
        elseif event.element.name == "fp_button_floor_up" and is_left_click then
            handle_floor_change_click(player, "up")

        -- Sets the selected floor to be the top one
        elseif event.element.name == "fp_button_floor_top" and is_left_click then
            handle_floor_change_click(player, "top")

        -- Repairs the current subfactory as well as possible
        elseif event.element.name == "fp_button_error_bar_repair" and is_left_click then
            handle_subfactory_repair(player)

        -- Reacts to a subfactory button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_subfactory_%d+$") then
            local subfactory_id = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_element_click(player, subfactory_id, click, direction)
            
            -- Changes the timescale of the current subfactory
        elseif string.find(event.element.name, "^fp_button_timescale_%d+$") and is_left_click then
            local timescale = tonumber(string.match(event.element.name, "%d+"))
            handle_subfactory_timescale_change(player, timescale)
            
        -- Reacts to any subfactory_pane item button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_subpane_[a-z-]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            _G["handle_" .. split_string[4] .. "_element_click"](player, split_string[5], click, direction)

        -- Reacts to a item group button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_item_group_[a-z-]+$") and is_left_click then
            local item_group_name = string.gsub(event.element.name, "fp_sprite%-button_item_group_", "")
            change_item_group_selection(player, item_group_name)

        -- Reacts to a recipe button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_recipe_[a-z-]+$") and is_left_click then
            local recipe_name = string.gsub(event.element.name, "fp_sprite%-button_recipe_", "")
            exit_modal_dialog(player, "cancel", {recipe_name=recipe_name})

        -- Reacts to the recipe button on an (assembly) line being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_line_recipe_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_line_recipe_click(player, line_id, click, direction)

        -- Reacts to the machine button on an (assembly) line being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_line_machine_%d+$") then
            local line_id = tonumber(string.match(event.element.name, "%d+"))
            handle_machine_change(player, line_id, nil, click, direction)
            
        -- Changes the machine of the selected (assembly) line
        elseif string.find(event.element.name, "^fp_sprite%-button_line_machine_%d+_[a-z0-9-]+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_machine_change(player, split_string[5], split_string[6], click, direction)

        -- Reacts to any preferences machine button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_preferences_machine_[a-z0-9-]+_[a-z0-9-]+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_preferences_machine_change(player, split_string[5], split_string[6])

        -- Reacts to any (assembly) line item button being pressed
        elseif string.find(event.element.name, "^fp_sprite%-button_line_%d+_[a-zA-Z]+_%d+$") then
            local split_string = ui_util.split(event.element.name, "_")
            handle_item_button_click(player, split_string[4], split_string[5], split_string[6], click, direction)
        
        else found = false end
    end

    -- Only reset hint if one of this mod's actual controls is pressed
    if found == true then 
        refresh_hint_message(player)
    else
        -- Refresh the previously selected textfield so no invalid text remains behind (disabled for now)
        --[[ if previously_selected_textfield ~= nil and previously_selected_textfield.valid then
            local subfactory_id = global.players[player.index].selected_subfactory_id
            local line_id = tonumber(string.match(previously_selected_textfield.name, "%d+"))
            previously_selected_textfield.text = Line.get_percentage(player, subfactory_id,
              Subfactory.get_selected_floor_id(player, subfactory_id), line_id)
        end ]]

        -- Remove focus from textfield so keyboard shortcuts work (not super reliable)
        if not string.find(event.element.name, "^fp_textfield_[a-z0-9-_]+$") then
            if player.gui.center["fp_frame_main_dialog"] ~= nil then
                player.gui.center["fp_frame_main_dialog"].focus()
            end
        end
        -- Select the text of the percentage textfield
        if string.find(event.element.name, "^fp_textfield_line_percentage_%d+$") then
            event.element.select_all()
            previously_selected_textfield = event.element
        end
    end
end)
require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")
require("ui.ui_util")
require("ui.event_handler")

-- TODO move the rest over to event_handler when all GUIs are redone

-- ** KEYBOARD SHORTCUTS **
script.on_event("fp_toggle_main_dialog", function(event)
    local player = game.get_player(event.player_index)
    main_dialog.toggle(player)
end)

script.on_event("fp_toggle_pause", function(event)
    local player = game.get_player(event.player_index)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if frame_main_dialog and frame_main_dialog.visible then
        local button_pause = frame_main_dialog["flow_titlebar"]["flow_titlebar_buttonbar"]["fp_button_titlebar_pause"]
        titlebar.handle_pause_button_click(player, button_pause)
    end
end)

script.on_event("fp_floor_up", function(event)
    local player = game.get_player(event.player_index)
    if ui_util.rate_limiting_active(player, event.input_name, event.input_name) then return end
    if main_dialog.is_in_focus(player) then production_titlebar.handle_floor_change_click(player, "up") end
end)

script.on_event("fp_refresh_production", function(event)
    local player = game.get_player(event.player_index)
    local subfactory = data_util.get("context", event.player_index).subfactory
    if main_dialog.is_in_focus(player) then calculation.update(player, subfactory, true) end
end)

script.on_event("fp_cycle_production_views", function(event)
    local player = game.get_player(event.player_index)
    if main_dialog.is_in_focus(player) then production_titlebar.change_view_state(player, nil) end
end)

script.on_event("fp_confirm_dialog", function(event)
    local player = game.get_player(event.player_index)
    if ui_util.rate_limiting_active(player, event.input_name, event.input_name) then return end
    modal_dialog.exit(player, "submit", {})
end)

script.on_event("fp_focus_searchfield", function(event)
    local player = game.get_player(event.player_index)
    if data_util.get("ui_state", event.player_index).modal_dialog_type == "product" then
        local textfield = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["flow_item_picker"]
          ["table_search_bar"]["fp_textfield_item_picker_search_bar"]
        ui_util.select_all(textfield)
    end
end)


-- ** LUA SHORTCUTS **
script.on_event(defines.events.on_lua_shortcut, function(event)
    local player = game.players[event.player_index]

    if event.prototype_name == "fp_open_interface" then
        main_dialog.toggle(player)
    end
end)


-- ** PLAYER GUI EVENTS **
script.on_event(defines.events.on_player_display_resolution_changed, function(event)
    main_dialog.refresh(game.get_player(event.player_index), true)
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
    main_dialog.refresh(game.get_player(event.player_index), true)
end)

-- Fires when the user makes a selection using a selection-tool
script.on_event(defines.events.on_player_selected_area, function(event)
    local player = game.get_player(event.player_index)

    if event.item == "fp_beacon_selector" and data_util.get("flags", player).selection_mode then
        if ui_util.rate_limiting_active(player, event.name, event.item) then return end
        beacon_dialog.leave_selection_mode(player, table_size(event.entities))
    end
end)

-- Fires when the item that the player is holding changes
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    -- If the cursor stack is not valid_for_read, it's empty, thus the selector has been put away
    if data_util.get("flags", player).selection_mode and not player.cursor_stack.valid_for_read then
        beacon_dialog.leave_selection_mode(player, nil)
    end
end)


-- ** GUI EVENTS **
-- Fires the user action of closing a dialog
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)

	if event.gui_type == defines.gui_type.custom and event.element and event.element.visible
      and string.find(event.element.name, "^fp_.+$") then
        -- Close or hide any modal dialog or leave selection mode
        if event.element.name == "fp_frame_modal_dialog" then
            if data_util.get("flags", player).selection_mode then beacon_dialog.leave_selection_mode(player, nil)
            else modal_dialog.exit(player, "cancel", {}) end

        -- Toggle the main dialog
        elseif event.element.name == "fp_frame_main_dialog" then
            main_dialog.toggle(player)

        end
	end
end)

-- Fires on any confirmation of a textfield
script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    -- Re-run calculations when the mining prod changes, or cancel custom mining prod 'mode'
    if element_name == "fp_textfield_mining_prod" then
        info_pane.handle_mining_prod_confirmation(player)

    -- Re-run calculations when a line percentage change is confirmed
    elseif string.find(element_name, "^fp_textfield_line_percentage_%d+$") then
        production_handler.handle_percentage_confirmation(player, event.element)

    --[[ -- Make sure submitting the export_string when importing actually imports
    elseif element_name == "fp_textfield_porter_string_import" then
        import_dialog.import_subfactories(player) ]]

    --[[ -- Submit any modal dialog, if it is open
    elseif data_util.get("ui_state", player).modal_dialog_type ~= nil then
        if ui_util.rate_limiting_active(player, "submit_modal_dialog", element_name) then return end
        modal_dialog.exit(player, "submit", {}) ]]

    else
        event_handler.handle_gui_event(event)

    end
end)


-- Fires on any checkbox/radiobutton change
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    --[[ local player = game.get_player(event.player_index)
    local element_name = event.element.name

    -- (Un)checks every porter-table rows' checkbox
    if element_name == "fp_checkbox_porter_master" then
        porter_dialog.set_all_checkboxes(player, event.element.state)

    -- Adjusts the porter dialog window after one of the subfactory checkboxes is clicked
    elseif string.find(element_name, "^fp_checkbox_porter_subfactory_[a-z]+_%d+$") then
        porter_dialog.adjust_after_checkbox_click(player)

    -- Toggles the selected general or production preference (This type/preference detection is stupid)
    elseif string.find(element_name, "^fp_checkbox_[a-z]+_preferences_[a-z_]+$") then
        local type = cutil.split(element_name, "_")[3]
        local preference = string.gsub(element_name, "fp_checkbox_" .. type .. "_preferences_", "")
        preferences_dialog.handle_checkbox_change(player, type, preference, event.element.state)

    end ]]

    event_handler.handle_gui_event(event)
end)

-- Fires on any switch change
script.on_event(defines.events.on_gui_switch_state_changed, function(event)
    local player = game.get_player(event.player_index)
    local element_name = event.element.name

    --[[ -- Changes the tutorial-mode preference
    if element_name == "fp_switch_tutorial_mode" then
        local new_state = ui_util.switch.convert_to_boolean(event.element.switch_state)
        tutorial_dialog.set_tutorial_mode(player, new_state) ]]

    -- Applies the disabled/hidden filter to the recipe dialog
    --[[ else ]]if string.find(element_name, "^fp_switch_recipe_filter_[a-z]+$") then
        local filter_name = string.gsub(element_name, "fp_switch_recipe_filter_", "")
        recipe_dialog.handle_filter_switch_flick(player, filter_name, event.element.switch_state)

    --[[ -- Refreshes the data attached to the clicked scope-switch
    elseif string.find(element_name, "^fp_switch_utility_scope_[a-z]+$") then
        local scope_type = string.gsub(element_name, "fp_switch_utility_scope_", "")
        utility_dialog.handle_scope_change(player, scope_type, event.element.switch_state) ]]

    else
        event_handler.handle_gui_event(event)

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

        --[[ -- Persists default beacon count changes
        elseif element_name == "fp_textfield_default_beacon_count" then
            data_util.get("preferences", player).mb_defaults.beacon_count = tonumber(event.element.text) ]]

        --[[ -- Dynamically en/disables the subfactory import button
        elseif element_name == "fp_textfield_porter_string_import" then
            import_dialog.handle_import_string_change(player, event.element) ]]

        --[[ -- Persists notes changes
        elseif element_name == "fp_text-box_notes" then
            utility_dialog.handle_notes_change(player, event.element) ]]

        -- Persists mining productivity changes
        elseif element_name == "fp_textfield_mining_prod" then
            info_pane.handle_mining_prod_change(player, event.element)

        -- Updates the product dialog amounts
        elseif string.find(element_name, "^fp_textfield_product_[a-z]+$") then
            local defined_by = string.gsub(element_name, "fp_textfield_product_", "")
            product_dialog.handle_product_amount_change(player, defined_by)

        -- Persists (assembly) line percentage changes
        elseif string.find(element_name, "^fp_textfield_line_percentage_%d+$") then
            production_handler.handle_percentage_change(player, event.element)

        -- Persists (assembly) line comment changes
        elseif string.find(element_name, "^fp_textfield_line_comment_%d+$") then
            production_handler.handle_comment_change(player, event.element)

        else
            event_handler.handle_gui_event(event)
        end
    end
end)


-- Fires on any change to a choose_elem_button
script.on_event(defines.events.on_gui_elem_changed, function(event)
    local player = game.get_player(event.player_index)

    -- Changes the reference belt for the currently open product
    if event.element.name == "fp_choose-elem-button_product_belts" then
        local belt_name = event.element.elem_value
        product_dialog.handle_belt_change(player, belt_name)

    --[[ -- Persists changes to the module/beacon defaults
    elseif string.find(event.element.name, "^fp_choose%-elem%-button_default_[a-z]+$") then
        preferences_dialog.handle_mb_defaults_change(player, event.element) ]]

    else
        event_handler.handle_gui_event(event)
    end
end)


-- Fires on any click on a GUI element
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    local ui_state = data_util.get("ui_state", player)
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
            main_dialog.toggle(player)

        -- Changes the pause_on_interface preference
        elseif element_name == "fp_button_titlebar_pause" then
            titlebar.handle_pause_button_click(player, event.element)

        -- Opens the tutorial dialog
        elseif element_name == "fp_button_titlebar_tutorial" then
            modal_dialog.enter(player, {type="tutorial"})

        --[[ -- Opens the tutorial dialog
        elseif element_name == "fp_button_tutorial_add_example" then
            tutorial_dialog.add_example_subfactory(player) ]]

        -- Opens the preferences dialog
        elseif element_name == "fp_button_titlebar_preferences" then
            modal_dialog.enter(player, {type="preferences"})

        -- Toggles the archive-view-mode
        elseif element_name == "fp_button_toggle_archive" then
            actionbar.toggle_archive_view(player)

        -- Opens utilitys dialog
        elseif element_name == "fp_button_open_utility_dialog" then
            modal_dialog.enter(player, {type="utility"})

        -- Changes into the manual override of the mining prod mode
        elseif element_name == "fp_button_mining_prod_override" then
            info_pane.override_mining_prod(player)

        -- Opens the add-product dialog
        elseif element_name == "fp_sprite-button_add_product" then
            modal_dialog.enter(player, {type="product", submit=true})

        -- Toggles the TopLevelItems-amount display state
        elseif element_name == "fp_button_item_amount_toggle" then
            production_titlebar.toggle_floor_total_display(player, event.element)

        -- Refreshes the production table
        elseif element_name == "fp_sprite-button_refresh_production" then
            calculation.update(player, ui_state.context.subfactory, true)

        -- Clears all the comments on the current floor
        elseif element_name == "fp_button_production_clear_comments" then
            production_handler.clear_recipe_comments(player)

        -- Repairs the current subfactory as well as possible
        elseif element_name == "fp_button_error_bar_repair" then
            error_bar.handle_subfactory_repair(player)

        -- Maxes the amount of modules on a modules-dialog
        elseif element_name == "fp_button_max_modules" then
            module_beacon_dialog.set_max_module_amount(player)

        -- Gives the player the beacon-selector
        elseif element_name == "fp_button_beacon_selector" then
            beacon_dialog.enter_selection_mode(player)

        -- Reacts to a modal dialog button being pressed
        elseif string.find(element_name, "^fp_button_modal_dialog_[a-z]+$") then
            local dialog_action = string.gsub(element_name, "fp_button_modal_dialog_", "")
            modal_dialog.exit(player, dialog_action, {})

        -- Reacts to a actionbar button being pressed
        elseif string.find(element_name, "^fp_button_actionbar_[a-z]+$") then
            local actionbar_action = string.gsub(element_name, "fp_button_actionbar_", "")
            actionbar[actionbar_action .. "_subfactory"](player)

        --[[ -- Reacts to an import/export porter button being pressed
        elseif string.find(element_name, "^fp_button_porter_subfactory_[a-z]+$") then
            local porter_action = string.gsub(element_name, "fp_button_porter_subfactory_", "")
            _G[porter_action .. "_dialog"][porter_action .. "_subfactories"](player) ]]

        -- Reacts to a subfactory button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_subfactory_%d+$") then
            local subfactory_id = tonumber(string.match(element_name, "%d+"))
            subfactory_bar.handle_subfactory_element_click(player, subfactory_id, click, direction, action, event.alt)

        -- Changes the timescale of the current subfactory
        elseif string.find(element_name, "^fp_button_timescale_%d+$") then
            local timescale = tonumber(string.match(element_name, "%d+"))
            info_pane.handle_subfactory_timescale_change(player, timescale)

        -- Reacts to any subfactory_pane item button being pressed (class name being a string is fine)
        elseif string.find(element_name, "^fp_sprite%-button_subpane_[a-zA-Z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            subfactory_pane["handle_" .. split_string[4] .. "_element_click"](player, split_string[5],
              click, direction, action, event.alt)

        -- Reacts to an item group button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_item_group_%d+$") then
            local picker_flow = event.element.parent.parent.parent
            local group_id = string.match(element_name, "%d+")
            item_picker.select_group(picker_flow, group_id)

        -- Reacts to an item picker button being pressed
        elseif string.find(element_name, "^fp_button_item_pick_%d+_%d+$") then
            local item_identifier = string.gsub(element_name, "fp_button_item_pick_", "")
            _G[ui_state.modal_dialog_type .. "_dialog"].handle_item_picker_click(player, item_identifier)

        -- Reacts to a recipe picker button being pressed
        elseif string.find(element_name, "^fp_button_recipe_pick_[0-9]+$") then
            local recipe_id = tonumber(string.match(element_name, "%d+"))
            recipe_dialog.attempt_adding_line(player, recipe_id)

        --[[ -- Reacts to a chooser element button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_chooser_element_[0-9_]+$") then
            local element_id = string.gsub(element_name, "fp_sprite%-button_chooser_element_", "")
            chooser_dialog.handle_element_click(player, element_id) ]]

        -- Reacts to a floor-changing button being pressed (up/top)
        elseif string.find(element_name, "^fp_button_floor_[a-z]+$") then
            local destination = string.gsub(element_name, "fp_button_floor_", "")
            production_titlebar.handle_floor_change_click(player, destination)

        -- Reacts to a change of the production pane view
        elseif string.find(element_name, "^fp_button_production_titlebar_view_[a-zA-Z-_]+$") then
            local view_name = string.gsub(element_name, "fp_button_production_titlebar_view_", "")
            production_titlebar.change_view_state(player, view_name)

        -- Reacts to the recipe button on an (assembly) line being pressed
        elseif string.find(element_name, "^fp_sprite%-button_line_recipe_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            production_handler.handle_line_recipe_click(player, line_id, click, direction, action, event.alt)

        -- Reacts to the machine button on an (assembly) line being pressed
        elseif string.find(element_name, "^fp_sprite%-button_line_machine_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            production_handler.handle_machine_change(player, line_id, nil, click, direction, event.alt)

        -- Changes the machine of the selected (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_machine_%d+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            production_handler.handle_machine_change(player, split_string[5], split_string[6], click, direction)

        -- Handles click on the add-module-button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_add_module_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            production_handler.handle_line_module_click(player, line_id, nil, click, direction, nil)

        -- Handles click on any module button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_module_%d+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            production_handler.handle_line_module_click(player, split_string[5], split_string[6], click,
              direction, action, event.alt)

        -- Handles click on the add-beacon-button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_add_beacon_%d+$") then
            local line_id = tonumber(string.match(element_name, "%d+"))
            production_handler.handle_line_beacon_click(player, line_id, nil, click, direction, nil)

        -- Handles click on any beacon (module or beacon) button on an (assembly) line
        elseif string.find(element_name, "^fp_sprite%-button_line_beacon_[a-z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            production_handler.handle_line_beacon_click(player, split_string[6], split_string[5], click,
              direction, action, event.alt)

        -- Handles click on any module/beacon button on a modules/beacons modal dialog
        elseif string.find(element_name, "^fp_sprite%-button_[a-z]+_selection_%d+_?%d*$") then
            module_beacon_dialog.handle_picker_click(player, event.element)

        --[[ -- Reacts to any default prototype preference button being pressed
        elseif string.find(element_name, "^fp_sprite%-button_preferences_[a-z]+_%d+_?%d*$") then
            local split_string = cutil.split(element_name, "_")
            preferences_dialog.handle_prototype_change(player, split_string[4], split_string[5], split_string[6], event.alt) ]]

        -- Reacts to any (assembly) line item button being pressed (strings for class names are fine)
        elseif string.find(element_name, "^fp_sprite%-button_line_%d+_[a-zA-Z]+_%d+$") then
            local split_string = cutil.split(element_name, "_")
            if split_string[5] == "Fuel" then
                production_handler.handle_fuel_button_click(player, split_string[4], click, direction, event.alt)
            else
                production_handler.handle_item_button_click(player, split_string[4], split_string[5],
                  split_string[6], click, direction, event.alt)
            end

        else
            event_handler.handle_gui_event(event)
        end
    end
end)
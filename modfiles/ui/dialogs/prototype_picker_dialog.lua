-- Contains the functionality used by all picker dialogs
picker = {groups_per_row = 6}


-- Adds a bar containing checkboxes to control whether enabled and hidden picks should be shown
function picker.refresh_filter_conditions(flow, disabled_state, hidden_state)
    -- Create filter conditions from scratch if they don't exist
    if flow["table_filter_conditions"] == nil then
        local table = flow.add{type="table", name="table_filter_conditions", column_count=2}
        table.vertical_centering = false
        table.style.horizontal_spacing = 16

        local label = table.add{type="label", name="label_filter_conditions", caption={"fp.show"}}
        label.style.top_margin = 2
        label.style.left_margin = 4

        local flow_switches = table.add{type="flow", name="flow_switches", direction="vertical"}
        ui_util.switch.add_on_off(flow_switches, "picker_filter_condition_disabled", disabled_state, 
          {"fp.unresearched_recipes"}, nil)
        ui_util.switch.add_on_off(flow_switches, "picker_filter_condition_hidden", hidden_state,
          {"fp.hidden_recipes"}, nil)

    -- Refresh the switch_states if the elements already exist
    else
        local flow_switches = flow["table_filter_conditions"]["flow_switches"]
        ui_util.switch.set_state(flow_switches, "picker_filter_condition_disabled", disabled_state)
        ui_util.switch.set_state(flow_switches, "picker_filter_condition_hidden", hidden_state)
    end
end


-- Adds a bar containing a search bar that is optionally hidden
function picker.refresh_search_bar(flow, search_term, visible)
    local table = flow["table_search_bar"]
    if table == nil then
        table = flow.add{type="flow", name="table_search_bar", direction="horizontal"}
        table.style.bottom_margin = 2
        table.style.horizontal_spacing = 12
        table.style.vertical_align = "center"
    else
        table.clear()
    end
    table.visible = visible

    table.add{type="label", name="label_search_bar", caption={"fp.search"}}
    local textfield = table.add{type="textfield", name="fp_textfield_picker_search_bar", text=search_term}
    textfield.style.width = 140
    ui_util.setup_textfield(textfield)
    if visible then textfield.focus() end
end


-- Adds a warning label to the dialog
function picker.refresh_warning_label(flow, message)
    local label = flow["label_warning_message"]
    if label == nil then
        label = flow.add{type="label", name="label_warning_message"}
        label.style.font = "fp-font-16p"
        ui_util.set_label_color(label, "red")
        label.style.bottom_margin = 4
    end
    if (message == "") then
        label.visible = false
        label.style.top_margin = 0
    else
        label.visible = true
        label.style.top_margin = 6
    end
    label.caption = message
end


-- Refreshes the actual picker panel, for the given object type and with the given visibility
-- (This function is optimized for performance, so not everything might be done in the obvious way)
function picker.refresh_picker_panel(flow, object_type, visible)
    local player = game.get_player(flow.player_index)

    local flow_picker_panel = flow["flow_picker_panel"]
    if flow_picker_panel == nil then
        flow_picker_panel = flow.add{type="flow", name="flow_picker_panel", direction="vertical"}
        flow_picker_panel.style.top_margin = 6

        local table_item_groups = flow_picker_panel.add{type="table", name="table_item_groups",
          column_count=picker.groups_per_row}
        table_item_groups.style.bottom_margin = 6
        table_item_groups.style.horizontal_spacing = 3
        table_item_groups.style.vertical_spacing = 3
        table_item_groups.style.minimal_width = picker.groups_per_row * (64 + 9)

        local formatted_objects = sorted_objects[object_type .. "s"]
        local undesirables = generator.undesirable_item_groups()[object_type]
        local group_id_cache, group_button_cache, subgroup_flow_cache, subgroup_table_cache = {}, {}, {}, {}

        for _, object in ipairs(formatted_objects) do
            local group_name = object.group.name
            local group_id = group_id_cache[group_name]
            if group_id == nil then
                group_id_cache[group_name] = (table_size(group_id_cache) + 1)
                group_id = table_size(group_id_cache)
            end

            if undesirables[group_name] == nil then  -- ignore undesirable item groups
                local button_group = group_button_cache[group_id]
                local scroll_pane_subgroups, table_subgroups = nil, nil
                if button_group == nil then
                    button_group = table_item_groups.add{type="sprite-button", name="fp_sprite-button_".. object_type ..
                      "_group_" .. group_id, sprite=("item-group/" .. group_name), style="fp_button_icon_medium_recipe",
                      tooltip=object.group.localised_name, mouse_button_filter={"left"}}
                    button_group.style.width = 70
                    button_group.style.height = 70
                    if devmode then button_group.tooltip = {"", button_group.tooltip, ("\n" .. group_name)} end
                    group_button_cache[group_id] = button_group

                    -- This only exists when button_group also exists
                    scroll_pane_subgroups = flow_picker_panel.add{type="scroll-pane", 
                      name="scroll-pane_subgroups_" .. group_id}
                    scroll_pane_subgroups.style.bottom_margin = 4
                    scroll_pane_subgroups.style.horizontally_stretchable = true
                    subgroup_flow_cache[group_id] = scroll_pane_subgroups

                    table_subgroups = scroll_pane_subgroups.add{type="table", name="table_subgroups", column_count=1}
                    table_subgroups.style.vertical_spacing = 3
                else
                    scroll_pane_subgroups = subgroup_flow_cache[group_id]
                    table_subgroups = scroll_pane_subgroups["table_subgroups"]
                end

                local subgroup_name = object.subgroup.name
                local table_subgroup = subgroup_table_cache[subgroup_name]
                if table_subgroup == nil then
                    table_subgroup = table_subgroups.add{type="table", name="table_subgroup_" .. subgroup_name,
                      column_count=12, style="fp_table_subgroup"}
                    subgroup_table_cache[subgroup_name] = table_subgroup
                end

                local button_object = table_subgroup.add{type="sprite-button", name=("fp_sprite-button_picker_"
                  .. object_type .. "_object_" .. object.identifier), sprite=object.sprite,
                  style="fp_button_icon_medium_recipe", tooltip=object.tooltip, mouse_button_filter={"left"}}
            end
        end
    end

    flow_picker_panel.visible = visible
end


-- Applies filters to the object picker, optionally also (re)applies an appropriate button style
-- (This function is not object-type-agnostic for performance reasons (minimizing function calls))
function picker.apply_filter(player, object_type, apply_button_style)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog_" .. object_type .. "_picker"]["flow_modal_dialog"]
    local warning_label = flow_modal_dialog["label_warning_message"]
    local search_term = flow_modal_dialog["table_search_bar"]["fp_textfield_picker_search_bar"].text:gsub("^%s*(.-)%s*$", "%1")
    search_term = string.lower(search_term)

    local disabled, hidden = nil, nil
    local existing_products, relevant_recipes, force_recipes = {}, {}, nil
    if object_type == "recipe" then
        local flow_switches = flow_modal_dialog["table_filter_conditions"]["flow_switches"]
        disabled = ui_util.switch.get_state(flow_switches, "picker_filter_condition_disabled", true)
        hidden = ui_util.switch.get_state(flow_switches, "picker_filter_condition_hidden", true)

        for _, recipe in pairs(get_ui_state(player).modal_data.recipes) do relevant_recipes[tostring(recipe.id)] = recipe end 
        force_recipes = player.force.recipes
    elseif apply_button_style then  -- object_type == "item"
        for _, product in pairs(Subfactory.get_in_order(get_context(player).subfactory, "Product")) do
            existing_products[product.proto.name] = true
        end
    end

    local first_visible_group = nil
    local visible_group_count = 0
    local total_group_count = 0
    local scroll_pane_height = 0
    for _, group_element in pairs(flow_modal_dialog["flow_picker_panel"]["table_item_groups"].children) do
        -- Dimensions need to be re-set here because they don't seem to survive a save-load-cycle
        group_element.style.width = 70
        group_element.style.height = 70

        local group_visible = false
        local specific_scroll_pane_height = 0
        local subgroup_count = 0

        local group_id = tonumber(string.match(group_element.name, "%d+"))
        local subgroup_elements = flow_modal_dialog["flow_picker_panel"]["scroll-pane_subgroups_".. group_id]
          ["table_subgroups"].children

        for _, subgroup_element in pairs(subgroup_elements) do
            local subgroup_visible = false
                
            for _, object_element in pairs(subgroup_element.children) do
                local visible = false
                
                if object_type == "item" then
                    local item = identifier_item_map[string.gsub(object_element.name, "fp_sprite%-button_picker_[a-z]+_object_", "")]

                    -- Set visibility of items (and item-groups) appropriately
                    if (not item.ingredient_only) and string.find(item.name, search_term, 1, true) then
                        visible = true

                        -- Only need to refresh button style if needed
                        if apply_button_style then
                            if existing_products[item.name] then
                                object_element.style = "fp_button_existing_product"
                                object_element.enabled = false
                            else
                                object_element.style = "fp_button_icon_medium_recipe"
                                object_element.enabled = true
                            end
                        end
                    end

                else  -- object_type == "recipe"
                    local recipe = relevant_recipes[string.gsub(object_element.name, "fp_sprite%-button_picker_[a-z]+_object_", "")]
                    
                    if recipe ~= nil then
                        local enabled = (recipe.custom) and true or force_recipes[recipe.name].enabled
                        
                        -- Boolean algebra is reduced here; to understand the intended meaning, take a look at this:
                        -- recipe.custom or (not (not disabled and not enabled) and not (not hidden and recipe.hidden))
                        if recipe.custom or ((disabled or enabled) and (hidden or not recipe.hidden)) then
                            visible = true

                            -- Only need to refresh button style if will actually be shown
                            if not enabled then object_element.style = "fp_button_icon_medium_disabled" 
                            elseif recipe.hidden then object_element.style = "fp_button_icon_medium_hidden"
                            else object_element.style = "fp_button_icon_medium_recipe" end
                        end
                    end
                end
                
                object_element.visible = visible
                if visible then subgroup_visible = true; group_visible = true end
            end
            
            subgroup_element.visible = subgroup_visible
            local object_count = table_size(subgroup_element.children)
            specific_scroll_pane_height = specific_scroll_pane_height +  math.ceil(object_count / 12) * 33
            subgroup_count = subgroup_count + 1
            
        end
        group_element.visible = group_visible
        specific_scroll_pane_height = specific_scroll_pane_height + subgroup_count * 3
        scroll_pane_height = math.max(scroll_pane_height, specific_scroll_pane_height)
        total_group_count = total_group_count + 1     
        
        if group_visible then
            visible_group_count = visible_group_count + 1
            if first_visible_group == nil then first_visible_group = group_id end
        end
    end

    -- Set selection to the first item group that is visible, respecting a previous selection
    local previously_selected_group = picker.get_selected_item_group(player, object_type)
    if (previously_selected_group == nil) or (not previously_selected_group.visible and first_visible_group ~= nil) then
        picker.select_item_group(player, object_type, first_visible_group)
    end

    -- Show warning message if no corresponding items/recipes are found
    if first_visible_group == nil then 
        picker.refresh_warning_label(flow_modal_dialog, {"fp.error_no_" .. object_type .. "_found"})
    else picker.refresh_warning_label(flow_modal_dialog, "") end
    local warning_label_height = (warning_label.caption == "") and 0 or 38
    
    -- Set item group height and picker panel heights to always add up to the same so the dialog window size doesn't change
    local flow_picker_panel = flow_modal_dialog["flow_picker_panel"]
    local group_row_count = math.ceil(visible_group_count / picker.groups_per_row)
    flow_picker_panel["table_item_groups"].style.height = group_row_count * 70
    
    -- Set scroll-pane height to be the same for all item groups
    local flow_modal_dialog_height = get_ui_state(player).flow_modal_dialog_height
    scroll_pane_height = scroll_pane_height + (math.ceil(total_group_count / picker.groups_per_row) * 70)
    local picker_panel_height = math.min(scroll_pane_height, (flow_modal_dialog_height - 100))
      - (group_row_count * 70) - warning_label_height
    for _, child in ipairs(flow_picker_panel.children_names) do
        if string.find(child, "^scroll%-pane_subgroups_%d+$") then
            flow_picker_panel[child].style.height = picker_panel_height
        end
    end
end

-- Returns the name of the currently selected item group, else if none is selected
function picker.get_selected_item_group(player, object_type)
    local picker_panel = player.gui.screen["fp_frame_modal_dialog_" .. object_type .. "_picker"]
      ["flow_modal_dialog"]["flow_picker_panel"]

    for _, group_button in pairs(picker_panel["table_item_groups"].children) do
        if group_button.style.name == "fp_button_icon_clicked" then
            return group_button
        end
    end
    return nil
end

-- Changes the selected item group to be the one specified by the given id
function picker.select_item_group(player, object_type, item_group_id)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog_" .. object_type .. "_picker"]
      ["flow_modal_dialog"]
    picker.refresh_warning_label(flow_modal_dialog, "")

    for _, group_button in pairs(flow_modal_dialog["flow_picker_panel"]["table_item_groups"].children) do
        local id = tonumber(string.match(group_button.name, "%d+"))
        local scroll_pane_items = flow_modal_dialog["flow_picker_panel"]["scroll-pane_subgroups_" .. id]
        if id == item_group_id then
            group_button.style = "fp_button_icon_clicked"
            group_button.enabled = false
            scroll_pane_items.visible = true
        else
            group_button.style = "fp_button_icon_medium_recipe"
            group_button.enabled = true
            scroll_pane_items.visible = false
        end
    end
end

-- Handles a new search term in the search bar
function picker.search(player)
    local ui_state = get_ui_state(player)
    local object_type = string.gsub(ui_state.modal_dialog_type, "_picker", "")
    picker.apply_filter(player, object_type, false)
end
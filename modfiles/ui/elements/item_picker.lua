-- Represents an item picker, including a search bar and a warning label
item_picker = {groups_per_row = 6}


-- Adds an item picker panel to the given parent element
function item_picker.create(parent)
    if parent["flow_item_picker"] ~= nil then return parent["flow_item_picker"] end
    local picker_flow = parent.add{type="flow", name="flow_item_picker", direction="vertical"}

    -- Search bar
    local table_search = picker_flow.add{type="flow", name="table_search_bar", direction="horizontal"}
    table_search.style.horizontal_spacing = 12
    table_search.style.vertical_align = "center"

    table_search.add{type="label", name="label_search_bar", caption={"fp.search"}}
    local textfield = table_search.add{type="textfield", name="fp_textfield_item_picker_search_bar"}
    textfield.style.width = 140
    ui_util.setup_textfield(textfield)

    -- Warning label
    local label_warning = picker_flow.add{type="label", name="label_warning_message", caption={"fp.error_no_item_found"}}
    ui_util.set_label_color(label_warning, "red")
    label_warning.style.top_margin = 8
    label_warning.style.font = "fp-font-bold-16p"
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog

    -- Item picker (optimized for performance, so not everything is done in the obvious way)
    local flow_picker_panel = picker_flow.add{type="flow", name="flow_picker_panel", direction="vertical"}
    flow_picker_panel.style.top_margin = 6

    local table_item_groups = flow_picker_panel.add{type="table", name="table_item_groups",
      column_count=item_picker.groups_per_row}
    table_item_groups.style.bottom_margin = 6
    table_item_groups.style.horizontal_spacing = 3
    table_item_groups.style.vertical_spacing = 3
    table_item_groups.style.minimal_width = item_picker.groups_per_row * (64 + 9)

    local undesirable_item_groups = {["creative-mod_creative-tools"]=false, ["im-tools"]=false}
    local group_id_cache, group_button_cache, subgroup_flow_cache, subgroup_table_cache = {}, {}, {}, {}

    for _, item in ipairs(sorted_items) do  -- global variable
        local group_name = item.group.name
        local group_id = group_id_cache[group_name]
        if group_id == nil then
            local cache_count = table_size(group_id_cache) + 1
            group_id_cache[group_name] = cache_count
            group_id = cache_count
        end

        if undesirable_item_groups[group_name] == nil then
            local button_group = group_button_cache[group_id]
            local scroll_pane_subgroups, table_subgroups = nil, nil

            if button_group == nil then
                local tooltip = (devmode) and {"", item.group.localised_name, ("\n" .. group_name)}
                  or item.group.localised_name
                button_group = table_item_groups.add{type="sprite-button", name="fp_sprite-button_item_group_"
                  .. group_id, sprite=("item-group/" .. group_name), style="fp_button_icon_medium_recipe",
                  tooltip=tooltip, mouse_button_filter={"left"}}
                button_group.style.width = 70
                button_group.style.height = 70
                group_button_cache[group_id] = button_group

                -- This only exists when button_group also exists
                scroll_pane_subgroups = flow_picker_panel.add{type="scroll-pane", name="scroll-pane_subgroups_" .. group_id}
                scroll_pane_subgroups.style.bottom_margin = 4
                scroll_pane_subgroups.style.horizontally_stretchable = true
                subgroup_flow_cache[group_id] = scroll_pane_subgroups

                table_subgroups = scroll_pane_subgroups.add{type="table", name="table_subgroups", column_count=1}
                table_subgroups.style.vertical_spacing = 3
            else
                scroll_pane_subgroups = subgroup_flow_cache[group_id]
                table_subgroups = scroll_pane_subgroups["table_subgroups"]
            end

            local subgroup_name = item.subgroup.name
            local table_subgroup = subgroup_table_cache[subgroup_name]

            if table_subgroup == nil then
                table_subgroup = table_subgroups.add{type="table", name="table_subgroup_" .. subgroup_name,
                  column_count=12, style="fp_table_subgroup"}
                subgroup_table_cache[subgroup_name] = table_subgroup
            end

            table_subgroup.add{type="sprite-button", name="fp_button_item_pick_" .. item.identifier,
              sprite=item.sprite, tooltip=item.localised_name, mouse_button_filter={"left"}}
        end
    end

    return picker_flow
end


-- Changes the selected item group to be the one of the given name
function item_picker.select_group(picker_flow, group_id)
    local flow_picker_panel = picker_flow["flow_picker_panel"]
    for _, group_button in pairs(flow_picker_panel["table_item_groups"].children) do
        local id = string.match(group_button.name, "%d+")
        local scroll_pane_items = flow_picker_panel["scroll-pane_subgroups_" .. id]

        if id == group_id then
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

-- Resets and focuses the item picker searchbar
function item_picker.reset_searchfield(picker_flow)
    local searchbar = picker_flow["table_search_bar"]["fp_textfield_item_picker_search_bar"]
    searchbar.text = ""
    searchbar.focus()
end


-- Filters the items shown according to the current search term
function item_picker.filter(picker_flow, searchterm, first_run)
    local flow_picker_panel = picker_flow["flow_picker_panel"]
    local warning_label = picker_flow["label_warning_message"]
    local ui_state = get_ui_state(game.get_player(picker_flow.player_index))
    local search_term = searchterm:gsub("^%s*(.-)%s*$", "%1"):lower()

    -- Check if the dialog is still open, don't bother filtering otherwise
    if ui_state.modal_data == nil then return end

    local existing_products = {}
    if first_run then  -- Need to re-apply button styles on first_run (ie. opening of the dialog)
        for _, product in pairs(Subfactory.get_in_order(ui_state.context.subfactory, "Product")) do
            existing_products[product.proto.name] = true
        end
    end

    local previously_selected_group = nil
    local first_visible_group = nil
    local visible_group_count = 0
    local total_group_count = 0
    local scroll_pane_height = 0
    
    for _, group_element in pairs(flow_picker_panel["table_item_groups"].children) do
        if group_element.style.name == "fp_button_icon_clicked" then previously_selected_group = group_element end

        -- Dimensions need to be re-set here because they don't seem to survive a save-load-cycle
        group_element.style.width = 70
        group_element.style.height = 70

        local group_visible = false
        local specific_scroll_pane_height = 0
        local subgroup_count = 0

        local group_id = string.match(group_element.name, "%d+")
        local subgroup_elements = flow_picker_panel["scroll-pane_subgroups_".. group_id]["table_subgroups"].children

        for _, subgroup_element in pairs(subgroup_elements) do
            local subgroup_visible = false
                
            for _, item_element in pairs(subgroup_element.children) do
                local item = identifier_item_map[string.gsub(item_element.name, "fp_button_item_pick_", "")]
                
                local visible = false
                -- Set visibility of items (and item-groups) appropriately (exception for rocket-part)
                if item.name == "rocket-part" or (not item.hidden and not item.ingredient_only
                  and string.find(item.name, search_term, 1, true)) then
                    visible = true

                    -- Only need to refresh button style if needed
                    if first_run then
                        if existing_products[item.name] then
                            item_element.style = "fp_button_existing_product"
                            item_element.enabled = false
                        else
                            item_element.style = "fp_button_icon_medium_recipe"
                            item_element.enabled = true
                        end
                    end
                end
                
                item_element.visible = visible
                if visible then subgroup_visible = true; group_visible = true end
            end
            
            subgroup_element.visible = subgroup_visible
            local item_count = table_size(subgroup_element.children)
            specific_scroll_pane_height = specific_scroll_pane_height +  math.ceil(item_count / 12) * 33
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
    if (previously_selected_group == nil) or (not previously_selected_group.visible and first_visible_group ~= nil) then
        item_picker.select_group(picker_flow, first_visible_group)
    end

    -- Show warning message if no corresponding items are found
    warning_label.visible = (first_visible_group == nil)
    local warning_label_height = (warning_label.visible) and 36 or 0
    
    -- Set item group height and picker panel heights to always add up to the same so the dialog window size doesn't change
    local group_row_count = math.ceil(visible_group_count / item_picker.groups_per_row)
    flow_picker_panel["table_item_groups"].style.height = group_row_count * 70
    
    -- Set scroll-pane height to be the same for all item groups
    scroll_pane_height = scroll_pane_height + (math.ceil(total_group_count / item_picker.groups_per_row) * 70)
    local picker_panel_height = math.min(scroll_pane_height, (ui_state.modal_data.dialog_maximal_height - 100))
      - (group_row_count * 70) - warning_label_height
    for _, child in ipairs(flow_picker_panel.children_names) do
        if string.find(child, "^scroll%-pane_subgroups_%d+$") then
            flow_picker_panel[child].style.height = picker_panel_height
        end
    end    
end

-- Handles any change to the given item picker textfield
function item_picker.handle_searchfield_change(textfield)
    if textfield and textfield.valid then
        local picker_flow = textfield.parent.parent
        item_picker.filter(picker_flow, textfield.text, false)
    end
end
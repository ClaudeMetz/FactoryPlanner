-- Handles populating the recipe dialog
function open_recipe_picker_dialog(flow_modal_dialog, args)
    local player = game.players[flow_modal_dialog.player_index]
    local subfactory_id = global.players[player.index].selected_subfactory_id
    local floor_id = Subfactory.get_selected_floor_id(player, subfactory_id)

    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog_recipe_picker"]["flow_modal_dialog"]
    if #flow_modal_dialog.children == 0 then create_recipe_picker_dialog_structure(player, flow_modal_dialog) end

    local recipe_name, error, show = run_preliminary_checks(player, args.product_name)
    if error ~= nil then
        queue_hint_message(player, error)
        exit_modal_dialog(player, "cancel", {})
    else
        -- One relevant, enabled, non-duplicate recipe found, add it immediately and exit dialog
        if recipe_name ~= nil then
            Floor.add_line(player, subfactory_id, floor_id, Line.init(player, global.all_recipes[recipe_name]))
            exit_modal_dialog(player, "cancel", {})
        
        -- Else show the appropriately filtered dialog
        else
            global.players[player.index].selected_product_name = args.product_name
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_enabled"].state = show.disabled
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_hidden"].state = show.hidden
            flow_modal_dialog["table_filter_conditions"]["textfield_search_recipe"].text = args.product_name
            apply_recipe_filter(player)
        end
    end
end

-- Handles closing of the recipe dialog
function close_recipe_picker_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local subfactory_id = global.players[player.index].selected_subfactory_id
    local floor_id = Subfactory.get_selected_floor_id(player, subfactory_id)

    if data ~= nil and data.recipe_name ~= nil then
        if Floor.recipe_exists(player, subfactory_id, floor_id, global.all_recipes[data.recipe_name]) then
            queue_hint_message(player, {"label.error_duplicate_recipe"})
        else
            Floor.add_line(player, subfactory_id, floor_id, Line.init(player, global.all_recipes[data.recipe_name]))
        end
    end

    global.players[player.index].selected_product_name = nil
    change_item_group_selection(player, "logistics")  -- Returns selection to the first item_group for consistency
end

-- No conditions needed for the recipe picker dialog
function get_recipe_picker_condition_instructions()
    return {data = {}, conditions = {}}
end


-- Creates the modal dialog to choose a recipe
function create_recipe_picker_dialog_structure(player, flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"label.add_recipe"}

    -- Filter conditions
    local table_filter_conditions = flow_modal_dialog.add{type="table", name="table_filter_conditions", column_count = 3}
    table_filter_conditions.style.bottom_margin = 8
    table_filter_conditions.style.horizontal_spacing = 16
    table_filter_conditions.add{type="label", name="label_filter_conditions", caption={"label.show"}}
    table_filter_conditions.add{type="checkbox", name="fp_checkbox_filter_condition_enabled", 
      caption={"checkbox.unresearched_recipes"}, state=false}
    table_filter_conditions.add{type="checkbox", name="fp_checkbox_filter_condition_hidden", 
      caption={"checkbox.hidden_recipes"}, state=false}

    table_filter_conditions.add{type="label", name="label_search_recipe", caption={"label.search"}}
    table_filter_conditions.add{type="textfield", name="textfield_search_recipe"}
    table_filter_conditions["textfield_search_recipe"].focus()
    local sprite_button_search = table_filter_conditions.add{type="sprite-button", 
      name="fp_sprite-button_search_recipe", sprite="utility/go_to_arrow"}
    sprite_button_search.style.height = 25
    sprite_button_search.style.width = 36

    -- Hides searchbox for users as it doesn't really serve a purpose right now
    if not global.devmode then
        table_filter_conditions["label_search_recipe"].visible = false
        table_filter_conditions["textfield_search_recipe"].visible = false
        table_filter_conditions["fp_sprite-button_search_recipe"].visible = false
    end

    local table_item_groups = flow_modal_dialog.add{type="table", name="table_item_groups", column_count=6}
    table_item_groups.style.bottom_margin = 6
    table_item_groups.style.horizontal_spacing = 3
    table_item_groups.style.vertical_spacing = 3
    table_item_groups.style.minimal_width = 6 * (64 + 8)

    local formatted_recipes = create_recipe_tree()
    local scroll_pane_height = 0
    for _, group in ipairs(formatted_recipes) do
        -- Item groups
        button_group = table_item_groups.add{type="sprite-button", name="fp_sprite-button_item_group_" .. group.name,
          sprite="item-group/" .. group.name, style="fp_button_icon_medium_recipe"}
        button_group.style.width = 70
        button_group.style.height = 70

        local scroll_pane_subgroups = flow_modal_dialog.add{type="scroll-pane", name="scroll-pane_subgroups_" .. group.name}
        scroll_pane_subgroups.style.bottom_margin = 4
        scroll_pane_subgroups.style.horizontally_stretchable = true
        scroll_pane_subgroups.visible = false
        local specific_scroll_pane_height = 0
        local table_subgroup = scroll_pane_subgroups.add{type="table", name="table_subgroup", column_count=1}
        table_subgroup.style.vertical_spacing = 3
        for _, subgroup in ipairs(group.subgroups) do
            -- Item subgroups
            local table_subgroup = table_subgroup.add{type="table", name="table_subgroup_" .. subgroup.name,
              column_count = 12}
            table_subgroup.style.horizontal_spacing = 2
            table_subgroup.style.vertical_spacing = 1
            for _, recipe in ipairs(subgroup.recipes) do
                -- Recipes
                local sprite = ui_util.get_recipe_sprite(player, recipe)
                local button_recipe = table_subgroup.add{type="sprite-button", name="fp_sprite-button_recipe_" .. recipe.name,
                  sprite=sprite, style="fp_button_icon_medium_recipe"}
                if recipe.hidden then button_recipe.style = "fp_button_icon_medium_hidden" end
                if not recipe.enabled then button_recipe.style = "fp_button_icon_medium_disabled" end
                button_recipe.tooltip = generate_recipe_tooltip(recipe)
                button_recipe.visible = false
                if (#table_subgroup.children_names - 1) % 12 == 0 then  -- new row
                    specific_scroll_pane_height = specific_scroll_pane_height + (32+1)
                end
            end
            specific_scroll_pane_height = specific_scroll_pane_height + 3  -- new subgroup
        end
        scroll_pane_height = math.max(scroll_pane_height, specific_scroll_pane_height)
    end
    -- Set scroll-pane height to be the same for all item groups
    for _, child in ipairs(flow_modal_dialog.children_names) do
        if string.find(child, "^scroll%-pane_subgroups_[a-z-]+$") then
            flow_modal_dialog[child].style.height = math.min(scroll_pane_height, 650)
        end
    end

    return frame_recipe_dialog
end

-- Separate function that extracts, formats and sorts all recipes so they can be displayed
-- (kinda crazy way to do all this, but not sure how so sort them otherwise)
function create_recipe_tree()
    -- First, categrorize the recipes according to the order of their group, subgroup and themselves
    local unsorted_recipe_tree = {}
    for _, recipe in pairs(global.all_recipes) do
        if unsorted_recipe_tree[recipe.group.order] == nil then
            unsorted_recipe_tree[recipe.group.order] = {}
        end
        local group = unsorted_recipe_tree[recipe.group.order]
        if group[recipe.subgroup.order] == nil then
            group[recipe.subgroup.order] = {}
        end
        local subgroup = group[recipe.subgroup.order]
        if subgroup[recipe.order] == nil then
            subgroup[recipe.order] = {}
        end
        table.insert(subgroup[recipe.order], recipe)
    end

    -- Then, sort them according to the orders into a new array
    -- Messy tree structure, but avoids modded situations where multiple recipes have the same order
    local sorted_recipe_tree = {}
    local group_name, subgroup_name
    for _, group in ui_util.pairsByKeys(unsorted_recipe_tree) do
        table.insert(sorted_recipe_tree, {name=nil, subgroups={}})
        local table_group = sorted_recipe_tree[#sorted_recipe_tree]
        for _, subgroup in ui_util.pairsByKeys(group) do
            table.insert(table_group.subgroups, {name=nil, recipes={}})
            local table_subgroup = table_group.subgroups[#table_group.subgroups]
            for _, recipe_order in ui_util.pairsByKeys(subgroup) do
                for _, recipe in ipairs(recipe_order) do
                    if not group_name then group_name = recipe.group.name end
                    if not subgroup_name then subgroup_name = recipe.subgroup.name end
                    table.insert(table_subgroup.recipes, recipe)
                end
            end
            table_subgroup.name = subgroup_name
            subgroup_name = nil
        end
        table_group.name = group_name
        group_name = nil
    end

    return sorted_recipe_tree
end


-- Serves the dual-purpose of setting the filter to include disabled recipes if no enabled ones are found
-- and, if there is only one that matches, to return a recipe name that can be added directly without the modal dialog
-- (This is more efficient than the big filter-loop, which would have to run twice otherwise)
-- (The logic is obtuse, but checks out)
function run_preliminary_checks(player, product_name)
    local subfactory_id = global.players[player.index].selected_subfactory_id
    local floor_id = Subfactory.get_selected_floor_id(player, subfactory_id)

    -- First determine all relevant recipes and the amount in each category (enabled and hidden)
    local relevant_recipes = {}
    local non_disabled_recipe_count = 0
    local non_hidden_recipe_count = 0
    for _, recipe in pairs(global.all_recipes) do
        if recipe_produces_product(recipe, product_name) and recipe.category ~= "handcrafting" then
            table.insert(relevant_recipes, recipe)
            if recipe.enabled then non_disabled_recipe_count = non_disabled_recipe_count + 1 end
            if not recipe.hidden then non_hidden_recipe_count = non_hidden_recipe_count + 1 end
        end
    end

    -- Set filters to the minimum that still shows at least one recipe
    local show = {disabled = false, hidden = false}
    if non_disabled_recipe_count == 0 then show.disabled = true end
    if non_hidden_recipe_count == 0 then show.hidden = true end

    -- Return result, format: return recipe, error-message, show
    if #relevant_recipes == 0 then
        return nil, {"label.error_no_relevant_recipe"}, show
    elseif #relevant_recipes == 1 then
        local recipe = relevant_recipes[1]
        if recipe.enabled then
            return recipe.name, nil, show
        else
            return nil, nil, show
        end
    else  -- 2+ relevant recipes
        return nil, nil, show
    end
end

-- Filters the recipes according to their enabled/hidden-attribute and the search-term
function apply_recipe_filter(player)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog_recipe_picker"]["flow_modal_dialog"]
    local unenabled = flow_modal_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_enabled"].state
    local hidden = flow_modal_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_hidden"].state
    local search_term =  flow_modal_dialog["table_filter_conditions"]["textfield_search_recipe"].text:gsub("%s+", "")

    local first_visible_group = nil
    for _, group_element in pairs(flow_modal_dialog["table_item_groups"].children) do
        local group_name = string.gsub(group_element.name, "fp_sprite%-button_item_group_", "")
        local group_visible = false
        for _, subgroup_element in pairs(flow_modal_dialog["scroll-pane_subgroups_".. group_name]["table_subgroup"].children) do
            local subgroup_visible = false
            for _, recipe_element in pairs(subgroup_element.children) do
                local recipe_name = string.gsub(recipe_element.name, "fp_sprite%-button_recipe_", "")
                local recipe = global.all_recipes[recipe_name]
                if ((not unenabled) and (not recipe.enabled)) or ((not hidden) and recipe.hidden) or 
                  (not recipe_produces_product(recipe, search_term)) then
                    recipe_element.visible = false
                else
                    if not recipe.enabled then recipe_element.style = "fp_button_icon_medium_disabled" 
                    elseif recipe.hidden then recipe_element.style = "fp_button_icon_medium_hidden"
                    else recipe_element.style = "fp_button_icon_medium_recipe" end

                    recipe_element.visible = true
                    subgroup_visible = true 
                    group_visible = true
                end
            end
            subgroup_element.visible = subgroup_visible
        end
        group_element.visible = group_visible
        if first_visible_group == nil and group_visible then 
            first_visible_group = group_name 
        end
    end

    if first_visible_group ~= nil then
        -- Set selection to the first item_group that is visible
        local selected_group = global.players[player.index].selected_item_group_name
        if selected_group == nil or flow_modal_dialog["table_item_groups"]["fp_sprite-button_item_group_" ..
          selected_group].visible == false then
            change_item_group_selection(player, first_visible_group)
        end
    end
end

-- Changes the selected item group to the specified one
function change_item_group_selection(player, item_group_name)
     local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog_recipe_picker"]["flow_modal_dialog"]
    -- First, change the currently selected one back to normal, if it exists
    local selected_item_group_name = global.players[player.index].selected_item_group_name
    if selected_item_group_name ~= nil then
        local sprite_button = flow_modal_dialog["table_item_groups"]
          ["fp_sprite-button_item_group_" .. selected_item_group_name]
        if sprite_button ~= nil then
            sprite_button.style = "fp_button_icon_medium_recipe"
            sprite_button.ignored_by_interaction = false
            flow_modal_dialog["scroll-pane_subgroups_" .. selected_item_group_name].visible = false
        end
    end

    -- Then, change the clicked one to the selected status
    global.players[player.index].selected_item_group_name = item_group_name
    local sprite_button = flow_modal_dialog["table_item_groups"]["fp_sprite-button_item_group_" .. item_group_name]
    sprite_button.style = "fp_button_icon_clicked"
    sprite_button.ignored_by_interaction = true
    flow_modal_dialog["scroll-pane_subgroups_" .. item_group_name].visible = true
end

-- Checks whether given recipe produces given product
function recipe_produces_product(recipe, product_name)
    if product_name == "" then return true end
    for _, product in ipairs(recipe.products) do
        if product.name == product_name then
            return true
        end
    end
    return false
end

-- Returns a formatted tooltip string for the given recipe
function generate_recipe_tooltip(recipe)
    local tooltip = recipe.localised_name
    if recipe.energy ~= nil then tooltip = {"", tooltip, "\n  ", {"tooltip.crafting_time"}, ":  ", recipe.energy} end

    local lists = {"ingredients", "products"}
    for _, item_type in ipairs(lists) do
        if recipe[item_type] ~= nil then
            tooltip = {"", tooltip, "\n  ", {"tooltip." .. item_type}, ":"}
            for _, item in ipairs(recipe[item_type]) do
                if item.amount == nil then item.amount = item.probability end
                tooltip = {"", tooltip, "\n    ", "[", item.type, "=", item.name, "] ", item.amount, "x ",
                  game[item.type .. "_prototypes"][item.name].localised_name}
            end
        end
    end

    return tooltip
end
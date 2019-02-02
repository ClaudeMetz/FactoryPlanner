-- Handles populating the recipe dialog
function open_recipe_dialog(player, product_id)
    local frame_recipe_dialog = player.gui.center["fp_frame_recipe_dialog"]
    if global["mods_changed"] then
        if frame_recipe_dialog ~= nil then frame_recipe_dialog.destroy() end
        frame_recipe_dialog = create_recipe_dialog_structure(player)
        global["mods_changed"] = false
    end

    frame_recipe_dialog["flow_recipe_dialog"]["table_filter_conditions"]["fp_checkbox_filter_condition_enabled"].state = false
    local product_name = get_product(global["selected_subfactory_id"], product_id).name
    local recipe_name = run_preliminary_checks(player, product_name)
    -- nil meaning that no single enabled and matching recipe has been found (either 0 or 2+)
    if recipe_name == nil then
        frame_recipe_dialog["flow_recipe_dialog"]["table_filter_conditions"]["textfield_search_recipe"].text = product_name
        apply_recipe_filter(player)
        toggle_main_dialog(player)
        frame_recipe_dialog.style.visible = true
    else
        game.print("add " .. recipe_name)
        -- add recipe to subfactory
    end
end

-- Handles closing of the recipe dialog
function close_recipe_dialog(player, recipe_name)
    if recipe_name ~= nil then
        game.print("add " .. recipe_name)
        -- add recipe to subfactory
    end

    change_item_group_selection(player, "logistics")  -- Returns selection to the first item_group for consistency
    player.gui.center["fp_frame_recipe_dialog"].style.visible = false
    toggle_main_dialog(player)
end


-- Creates the modal dialog to choose a recipe
function create_recipe_dialog_structure(player, search_term)
    local frame_recipe_dialog = player.gui.center.add{type="frame", name="fp_frame_recipe_dialog", direction="vertical"}
    frame_recipe_dialog.caption = {"label.add_recipe"}
    frame_recipe_dialog.style.visible = false
    local flow_recipe_dialog = frame_recipe_dialog.add{type="flow", name="flow_recipe_dialog", direction="vertical"}

    local button_bar = frame_recipe_dialog.add{type="flow", name="flow_recipe_dialog_button_bar", direction="horizontal"}
    button_bar.style.minimal_width = 220
    button_bar.add{type="button", name="fp_button_recipe_dialog_cancel", caption={"button-text.cancel"}, 
        style="fp_button_with_spacing"}

    local undesirables = undesirable_recipes()

    -- Filter conditions
    local table_filter_conditions = flow_recipe_dialog.add{type="table", name="table_filter_conditions", column_count = 3}
    table_filter_conditions.style.bottom_padding = 6
    table_filter_conditions.style.horizontal_spacing = 8
    table_filter_conditions.add{type="label", name="label_filter_conditions", caption={"label.show"}}
    table_filter_conditions.add{type="checkbox", name="fp_checkbox_filter_condition_enabled", 
      caption={"checkbox.unresearched_recipes"}, state=false}
    table_filter_conditions.add{type="checkbox", name="fp_checkbox_filter_condition_hidden", 
      caption={"checkbox.hidden_recipes"}, state=false}

    table_filter_conditions.add{type="label", name="label_search_recipe", caption={"label.search"}}
    table_filter_conditions.add{type="textfield", name="textfield_search_recipe", text=search_term}
    table_filter_conditions["textfield_search_recipe"].focus()
    local sprite_button_search = table_filter_conditions.add{type="sprite-button", 
      name="fp_sprite-button_search_recipe", sprite="utility/go_to_arrow"}
    sprite_button_search.style.height = 25
    sprite_button_search.style.width = 36

    -- Hides searchbox for users as it doesn't really serve a purpose right now
    if not global["devmode"] then
        table_filter_conditions["label_search_recipe"].style.visible = false
        table_filter_conditions["textfield_search_recipe"].style.visible = false
        table_filter_conditions["fp_sprite-button_search_recipe"].style.visible = false
    end

    local table_item_groups = flow_recipe_dialog.add{type="table", name="table_item_groups", column_count=6}
    table_item_groups.style.horizontal_spacing = 3
    table_item_groups.style.vertical_spacing = 3
    table_item_groups.style.minimal_width = 6 * (64 + 1)

    local formatted_recipes = create_recipe_tree()
    local scroll_pane_height = 0
    for _, group in ipairs(formatted_recipes) do
        -- Item groups
        button_group = table_item_groups.add{type="sprite-button", name="fp_sprite-button_item_group_" .. group.name,
          sprite="item-group/" .. group.name, style="fp_button_icon_recipe"}
        button_group.style.width = 64
        button_group.style.height = 64

        local scroll_pane_subgroups = flow_recipe_dialog.add{type="scroll-pane", name="scroll-pane_subgroups_" .. group.name}
        scroll_pane_subgroups.style.bottom_padding = 6
        scroll_pane_subgroups.style.horizontally_stretchable = true
        scroll_pane_subgroups.style.visible = false
        local specific_scroll_pane_height = -20  -- offsets the height-increase on the last row which is superfluous
        local table_subgroup = scroll_pane_subgroups.add{type="table", name="table_subgroup", column_count=1}
        table_subgroup.style.vertical_spacing = 4
        for _, subgroup in ipairs(group.subgroups) do
            -- Item subgroups
            local table_subgroup = table_subgroup.add{type="table", name="table_subgroup_" .. subgroup.name,
              column_count = 12}
            table_subgroup.style.horizontal_spacing = 2
            table_subgroup.style.vertical_spacing = 2
            for _, recipe in ipairs(subgroup.recipes) do
                if undesirables[recipe.name] ~= false and recipe.category ~= "handcrafting" then
                    -- Recipes
                    local button_recipe = table_subgroup.add{type="sprite-button", name="fp_sprite-button_recipe_" .. recipe.name,
                      sprite="recipe/" .. recipe.name, style="fp_button_icon_recipe"}
                    if recipe.hidden then button_recipe.style = "fp_button_icon_hidden" end
                    if not recipe.enabled then button_recipe.style = "fp_button_icon_disabled" end
                    button_recipe.tooltip = generate_recipe_tooltip(recipe)
                    button_recipe.style.visible = false
                    if (#table_subgroup.children_names - 1) % 12 == 0 then  -- new row
                        specific_scroll_pane_height = specific_scroll_pane_height + (28+2)
                    end
                end
            end
            specific_scroll_pane_height = specific_scroll_pane_height + 4  -- new subgroup
        end
        scroll_pane_height = math.max(scroll_pane_height, specific_scroll_pane_height)
    end
    -- Set scroll-pane height to be the same for all item groups
    for _, child in ipairs(flow_recipe_dialog.children_names) do
        if string.find(child, "^scroll%-pane_subgroups_[a-z-]+$") then
            flow_recipe_dialog[child].style.height = math.min(scroll_pane_height, 650)
        end
    end

    return frame_recipe_dialog
end

-- Separate function that extracts, formats and sorts all recipes so they can be displayed
-- (kinda crazy way to do all this, but not sure how so sort them otherwise)
function create_recipe_tree()
    local recipes = game.forces.player.recipes

    -- First, categrorize the recipes according to the order of their group, subgroup and themselves
    local unsorted_recipe_tree = {}
    for _, recipe in pairs(recipes) do
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
    for _, group in pairsByKeys(unsorted_recipe_tree) do
        table.insert(sorted_recipe_tree, {name=nil, subgroups={}})
        local table_group = sorted_recipe_tree[#sorted_recipe_tree]
        for _, subgroup in pairsByKeys(group) do
            table.insert(table_group.subgroups, {name=nil, recipes={}})
            local table_subgroup = table_group.subgroups[#table_group.subgroups]
            for _, recipe_order in pairsByKeys(subgroup) do
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

-- Returns the names of the recipes that shouldn't be included
function undesirable_recipes()
    local undesirables = 
    {
        ["small-plane"] = false,
        ["electric-energy-interface"] = false,
        ["railgun"] = false,
        ["railgun-dart"] = false,
        ["player-port"] = false
    }

    -- Leaves loaders in if LoaderRedux is loaded
    if game.active_mods["LoaderRedux"] == nil then
        undesirables["loader"] = false
        undesirables["fast-loader"] = false
        undesirables["express-loader"] = false
    end

    return undesirables
end


-- Serves the dual-purpose of setting the filter to include disabled recipes if no enabled ones are found
-- and, if there is only one that matches, to return a recipe name that can be directly added without the modal dialog
-- (This is more efficient than the big filter-loop, which would have to run twice otherwise)
-- (Also, the logic is obtuse, but checks out)
function run_preliminary_checks(player, product_name)
    local flow_recipe_dialog = player.gui.center["fp_frame_recipe_dialog"]["flow_recipe_dialog"]
    local recipes = game.forces.player.recipes

    local enabled = {}
    local disabled_count = 0
    for _, recipe in pairs(recipes) do
        if recipe_produces_product(recipe, product_name) then
            if recipe.enabled then
                table.insert(enabled, recipe.name)
            else
                disabled_count = disabled_count +1
            end
        end
    end
    
    if #enabled == 0 then
        flow_recipe_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_enabled"].state = true
    elseif #enabled == 1 and disabled_count == 0 then
        return enabled[1]  -- all other cases return nil
    end
    return nil  -- meaning recipe dialog has to be shown
end


-- Filters the recipes according to their enabled/hidden-attribute and the search-term
function apply_recipe_filter(player)
    local flow_recipe_dialog = player.gui.center["fp_frame_recipe_dialog"]["flow_recipe_dialog"]
    local unenabled = flow_recipe_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_enabled"].state
    local hidden = flow_recipe_dialog["table_filter_conditions"]["fp_checkbox_filter_condition_hidden"].state
    local search_term =  flow_recipe_dialog["table_filter_conditions"]["textfield_search_recipe"].text:gsub("%s+", "")
    local recipes = game.forces.player.recipes

    local first_visible_group = nil
    for _, group_element in pairs(flow_recipe_dialog["table_item_groups"].children) do
        local group_name = string.gsub(group_element.name, "fp_sprite%-button_item_group_", "")
        local group_visible = false
        for _, subgroup_element in pairs(flow_recipe_dialog["scroll-pane_subgroups_".. group_name]["table_subgroup"].children) do
            local subgroup_visible = false
            for _, recipe_element in pairs(subgroup_element.children) do
                local recipe_name = string.gsub(recipe_element.name, "fp_sprite%-button_recipe_", "")
                local recipe = recipes[recipe_name]
                if ((not unenabled) and (not recipe.enabled)) or ((not hidden) and recipe.hidden) or 
                  (not recipe_produces_product(recipe, search_term)) then
                    recipe_element.style.visible = false
                else
                    if not recipe.enabled then recipe_element.style = "fp_button_icon_disabled" 
                    elseif recipe.hidden then recipe_element.style = "fp_button_icon_hidden"
                    else recipe_element.style = "fp_button_icon_recipe" end

                    recipe_element.style.visible = true
                    subgroup_visible = true 
                    group_visible = true
                end
            end
            subgroup_element.style.visible = subgroup_visible
        end
        group_element.style.visible = group_visible
        if first_visible_group == nil and group_visible then 
            first_visible_group = group_name 
        end
    end

    if first_visible_group ~= nil then
        -- Set selection to the first item_group that is visible
        local selected_group = global["selected_item_group_name"]
        if selected_group == nil or flow_recipe_dialog["table_item_groups"]["fp_sprite-button_item_group_" ..
          selected_group].style.visible == false then
            change_item_group_selection(player, first_visible_group)
        end
    end
end

-- Changes the selected item group to the specified one
function change_item_group_selection(player, item_group_name)
    local flow_recipe_dialog = player.gui.center["fp_frame_recipe_dialog"]["flow_recipe_dialog"]
    -- First, change the currently selected one back to normal, if it exists
    if global["selected_item_group_name"] ~= nil then
        local sprite_button = flow_recipe_dialog["table_item_groups"]
          ["fp_sprite-button_item_group_" .. global["selected_item_group_name"]]
        if sprite_button ~= nil then
            sprite_button.style = "fp_button_icon_recipe"
            sprite_button.ignored_by_interaction = false
            flow_recipe_dialog["scroll-pane_subgroups_" .. global["selected_item_group_name"]].style.visible = false
        end
    end

    -- Then, change the clicked one to the selected status
    global["selected_item_group_name"] = item_group_name
    local sprite_button = flow_recipe_dialog["table_item_groups"]["fp_sprite-button_item_group_" .. item_group_name]
    sprite_button.style = "fp_button_icon_clicked"
    sprite_button.ignored_by_interaction = true
    flow_recipe_dialog["scroll-pane_subgroups_" .. item_group_name].style.visible = true
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
    local prototypes = {[1] = game.item_prototypes, [2] = game.fluid_prototypes}
    local tooltip = {"", recipe.localised_name, "\n  ", {"tooltip.crafting_time"}, ":  ", recipe.energy,}

    local lists = {"ingredients", "products"}
    for _, item_type in ipairs(lists) do
        tooltip = {"", tooltip, "\n  ", {"tooltip." .. item_type}, ":"}
        local t
        for _, item in ipairs(recipe[item_type]) do
            if item.type == "item" then t = 1 else t = 2 end
            if item.amount == nil then item.amount = item.probability end
            tooltip = {"", tooltip, "\n    ", item.amount, "x ", prototypes[t][item.name].localised_name}
        end
    end

    return tooltip
end

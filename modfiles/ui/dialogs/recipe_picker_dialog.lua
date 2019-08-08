-- Handles populating the recipe picker dialog
function open_recipe_picker_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local product = ui_state.selected_object

    flow_modal_dialog.parent.caption = {"label.add_recipe"}
    flow_modal_dialog.style.bottom_margin = 8

    local recipe_id, error, show = run_preliminary_checks(player, product)
    if error ~= nil then
        ui_util.message.enqueue(player, error, "error", 1)
        exit_modal_dialog(player, "cancel", {})
    else
        -- If 1 relevant, enabled, non-duplicate recipe is found, add it immediately and exit dialog
        if recipe_id ~= nil then
            local line = Line.init(player, Recipe.init_by_id(recipe_id), nil)
            -- If line is false, no compatible machine has been found (ingredient limit)
            if line == false then
                ui_util.message.enqueue(player, {"label.error_no_compatible_machine"}, "error", 1)
            else
                Floor.add(ui_state.context.floor, line)
                update_calculations(player, ui_state.context.subfactory)
                if show.message ~= nil then ui_util.message.enqueue(player, show.message.text, show.message.type, 1) end
            end
            exit_modal_dialog(player, "cancel", {})
        
        else  -- Otherwise, show the appropriately filtered dialog
            picker.refresh_filter_conditions(flow_modal_dialog, {"checkbox.unresearched_recipes"}, {"checkbox.hidden_recipes"})
            picker.refresh_search_bar(flow_modal_dialog, product.proto.name, false)
            picker.refresh_warning_label(flow_modal_dialog, "")
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_picker_filter_condition_disabled"].state = show.disabled
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_picker_filter_condition_hidden"].state = show.hidden
            picker.refresh_picker_panel(flow_modal_dialog, "recipe", true)

            picker.select_item_group(player, "recipe", "logistics")
            picker.apply_filter(player, "recipe", true)
        end
    end
end


-- Reacts to either the disabled or hidden radiobutton being pressed
function handle_filter_radiobutton_click(player, type, state)
    local ui_state = get_ui_state(player)

    -- Remember the user selection for this type of filter
    ui_state.recipe_filter_preferences[type] = state

    picker.apply_filter(player, "recipe", false)
end

-- Reacts to a picker recipe button being pressed
function handle_picker_recipe_click(player, button)
    local context = get_context(player)
    local recipe_id = tonumber(string.match(button.name, "%d+"))
    
    local line = Line.init(player, Recipe.init_by_id(recipe_id), nil)
    if line == false then
        ui_util.message.enqueue(player, {"label.error_no_compatible_machine"}, "error", 1)
    else
        Floor.add(context.floor, line)
        update_calculations(player, context.subfactory)
    end
    exit_modal_dialog(player, "cancel", {})
end


-- Serves the dual-purpose of setting the filter to include disabled recipes if no enabled ones are found
-- and, if there is only one that matches, to return a recipe name that can be added directly without the modal dialog
-- (This is more efficient than the big filter-loop, which would have to run twice otherwise)
function run_preliminary_checks(player, product)
    local force_recipes = player.force.recipes
    local relevant_recipes = {}
    local counts = {
        disabled = 0,
        hidden = 0,
        disabled_hidden = 0
    }
    if item_recipe_map[product.proto.type][product.proto.name] ~= nil then  -- this being nil means that the item has no recipes
        for _, recipe in pairs(global.all_recipes.recipes) do
            local force_recipe = force_recipes[recipe.name]
            if recipe_produces_product(player, recipe, product.proto.type, product.proto.name) then
                -- Only add recipes that exist on the current force
                if force_recipe ~= nil then
                    table.insert(relevant_recipes, recipe)
                    if not force_recipe.enabled and force_recipe.hidden then
                        counts.disabled_hidden = counts.disabled_hidden + 1
                    elseif not force_recipe.enabled then counts.disabled = counts.disabled + 1
                    elseif force_recipe.hidden then counts.hidden = counts.hidden + 1 end
                -- Add custom recipes by default
                elseif is_custom_recipe(player, recipe, true) then
                    table.insert(relevant_recipes, recipe)
                end
            end
        end
    end
    
    -- Set filters to try and show at least one recipe, should one exist, incorporating user preferences
    -- (This logic is probably inefficient, but it's clear and way faster than the loop above anyways)
    local user_prefs = get_ui_state(player).recipe_filter_preferences
    local show = {}
    local relevant_recipes_count = table_size(relevant_recipes)
    if relevant_recipes_count - counts.disabled - counts.hidden - counts.disabled_hidden > 0 then
        show.disabled = user_prefs.disabled or false
        show.hidden = user_prefs.hidden or false
    elseif relevant_recipes_count - counts.hidden - counts.disabled_hidden > 0 then
        show.disabled = true
        show.hidden = user_prefs.hidden or false
    else
        show.disabled = true
        show.hidden = true
    end
    
    -- Return result, format: return recipe, error-message, show
    if relevant_recipes_count == 0 then
        return nil, {"label.error_no_relevant_recipe"}, show
    elseif relevant_recipes_count == 1 then
        local chosen_recipe = relevant_recipes[1]
        -- Show hint if adding unresearched recipe (no hints on custom recipes)
        if not is_custom_recipe(player, chosen_recipe, true) and not force_recipes[chosen_recipe.name].enabled then
            show.message={text={"label.hint_disabled_recipe"}, type="warning"}
        end
        return chosen_recipe.id, nil, show
    else  -- 2+ relevant recipes
        return nil, nil, show
    end
end


-- Returns all recipes
function get_picker_recipes()
    return global.all_recipes.recipes
end

-- Returns the string identifier for the given recipe
function generate_recipe_identifier(recipe)
    return recipe.id
end

-- Returns the recipe described by the identifier
function get_recipe(identifier)
    return global.all_recipes.recipes[tonumber(identifier)]
end

-- Generates the tooltip string for the given recipe
function generate_recipe_tooltip(recipe)
    local tooltip = recipe.localised_name
    if recipe.energy ~= nil then 
        tooltip = {"", tooltip, "\n  ", {"tooltip.crafting_time"}, ":  ", recipe.energy}
    end

    local lists = {"ingredients", "products"}
    for _, item_type in ipairs(lists) do
        tooltip = {"", tooltip, "\n  ", {"tooltip." .. item_type}, ":"}
        if #recipe[item_type] == 0 then
            tooltip = {"", tooltip, "\n    ", {"tooltip.none"}}
        else
            for _, item in ipairs(recipe[item_type]) do
                -- Determine the actual amount of items that are consumed/produced
                -- (This function incidentally handles ingredients as well)
                produced_amount = data_util.determine_product_amount(item)
            
                tooltip = {"", tooltip, "\n    ", "[", item.type, "=", item.name, "] ", produced_amount, "x ",
                  game[item.type .. "_prototypes"][item.name].localised_name}
            end
        end
    end

    return tooltip
end

-- Returns true when the given recipe produces the given product
function recipe_produces_product(player, recipe, product_type, product_name)
    -- Exclude barreling recipes according to preference
    if (get_preferences(player).ignore_barreling_recipes and (recipe.subgroup.name == "empty-barrel"
      or recipe.subgroup.name == "fill-barrel")) then
        return false
    else
        -- Checks specific type, if it is given
        if product_type ~= nil then
            return (item_recipe_map[product_type][product_name][recipe.name] ~= nil)
            
        -- Otherwise, looks through all types
        else
            local product_types = {"item", "fluid"}
            for _, type in ipairs(product_types) do
                if item_recipe_map[type][product_name] ~= nil 
                  and item_recipe_map[type][product_name][recipe.name] ~= nil then
                    return true
                end
            end
            return false  -- return false if no product is found
        end
    end
end

-- Returns true if this recipe is a custom one, or if the recipe is the custom one for rocket building,
-- it returns the enabled state of the recipe for a rocket-part
-- If existence_only is true, it return true for any custom recipe, even if it is not enabled
function is_custom_recipe(player, recipe, existence_only)
    if (string.match(recipe.name, "^impostor-.*")) then
        return true
    elseif recipe.name == "fp-space-science-pack" then
        local space_science_recipe = player.force.recipes["rocket-part"]
        if existence_only or (space_science_recipe ~= nil and space_science_recipe.enabled) then
            return true
        else
            return false
        end
    end
end
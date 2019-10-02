-- Handles populating the recipe picker dialog
function open_recipe_picker_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local product = ui_state.selected_object

    flow_modal_dialog.parent.caption = {"label.add_recipe"}
    flow_modal_dialog.style.bottom_margin = 8

    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local result, error, show = run_preliminary_checks(player, product)
    
    local function refresh_unfiltered_dialog()
        picker.refresh_filter_conditions(flow_modal_dialog, show.disabled, show.hidden)
        picker.refresh_search_bar(flow_modal_dialog, product.proto.name, false)
        picker.refresh_warning_label(flow_modal_dialog, "")
        picker.refresh_picker_panel(flow_modal_dialog, "recipe", true)
    end

    if error ~= nil then
        ui_util.message.enqueue(player, error, "error", 2)  -- lifetime of 2 so it survives the first refresh
        exit_modal_dialog(player, "cancel", {})
    else
        -- If 1 relevant, enabled, non-duplicate recipe is found, add it immediately and exit dialog
        if type(result) == "number" then
            local line = Line.init(player, Recipe.init_by_id(result), nil)
            -- If line is false, no compatible machine has been found (ingredient limit)
            if line == false then
                ui_util.message.enqueue(player, {"label.error_no_compatible_machine"}, "error", 2)
            else
                Floor.add(ui_state.context.floor, line)
                calculation.update(player, ui_state.context.subfactory)
                if show.message ~= nil then ui_util.message.enqueue(player, show.message.text, show.message.type, 1) end
            end

            refresh_unfiltered_dialog() -- already create it here so auto_center works correctly
            exit_modal_dialog(player, "cancel", {})
        
        else  -- Otherwise, show the appropriately filtered dialog
            refresh_unfiltered_dialog()
            picker.select_item_group(player, "recipe", "logistics")
            ui_state.modal_data = result
            picker.apply_filter(player, "recipe", nil)
        end
    end
end


-- Reacts to either the disabled or hidden switches being flicked
function handle_filter_switch_flick(player, type, state)
    local ui_state = get_ui_state(player)
    -- Remember the user selection for this type of filter
    ui_state.recipe_filter_preferences[type] = ui_util.switch.convert_to_boolean(state)
    picker.apply_filter(player, "recipe", nil)
end

-- Reacts to a picker recipe button being pressed
function handle_picker_recipe_click(player, button)
    local context = get_context(player)
    local recipe_id = tonumber(string.match(button.name, "%d+"))
    
    local line = Line.init(player, Recipe.init_by_id(recipe_id), nil)
    if line == false then
        ui_util.message.enqueue(player, {"label.error_no_compatible_machine"}, "error", 2)
    else
        Floor.add(context.floor, line)
        calculation.update(player, context.subfactory)
    end
    exit_modal_dialog(player, "cancel", {})
end


-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter and,
-- if there is only one that matches, to return a recipe name that can be added directly without the modal dialog
function run_preliminary_checks(player, product)
    local force_recipes = player.force.recipes
    local relevant_recipes = {}
    local counts = {
        disabled = 0,
        hidden = 0,
        disabled_hidden = 0
    }
    
    local map = item_recipe_map[product.proto.type][product.proto.name]
    if map ~= nil then  -- this being nil means that the item has no recipes
        local preferences = get_preferences(player)
        for recipe_id, _ in pairs(map) do
            local recipe = global.all_recipes.recipes[recipe_id]
            local force_recipe = force_recipes[recipe.name]

            -- Add custom recipes by default
            if recipe.custom then
                table.insert(relevant_recipes, recipe)

            -- Only add recipes that exist on the current force (and aren't preferenced-out)
            elseif force_recipe ~= nil and not ((preferences.ignore_barreling_recipes and recipe.barreling)
              or (preferences.ignore_recycling_recipes and recipe.recycling)) then
                table.insert(relevant_recipes, recipe)

                if not force_recipe.enabled and force_recipe.hidden then
                    counts.disabled_hidden = counts.disabled_hidden + 1
                elseif not force_recipe.enabled then counts.disabled = counts.disabled + 1
                elseif force_recipe.hidden then counts.hidden = counts.hidden + 1 end
            end
        end
    end

    -- Set filters to try and show at least one recipe, should one exist, incorporating user preferences
    -- (This logic is probably inefficient, but it's clear and way faster than the loop above anyways)
    local show = {}
    local user_prefs = get_ui_state(player).recipe_filter_preferences
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
        if not chosen_recipe.custom and not force_recipes[chosen_recipe.name].enabled then
            show.message={text={"label.hint_disabled_recipe"}, type="warning"}
        end
        return chosen_recipe.id, nil, show
    else  -- 2+ relevant recipes
        return relevant_recipes, nil, show
    end
end
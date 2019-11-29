-- Handles populating the recipe dialog
function open_recipe_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local product = ui_state.selected_object

    flow_modal_dialog.parent.caption = {"fp.add_recipe"}

    -- Result is either the single possible recipe_id, or a table of relevant recipes
    local result, error, show = run_preliminary_checks(player, product, ui_state.modal_data.production_type)

    if error ~= nil then
        ui_util.message.enqueue(player, error, "error", 2)
        exit_modal_dialog(player, "cancel", {})
    else
        -- If 1 relevant, enabled, non-duplicate recipe is found, add it immediately and exit dialog
        if type(result) == "number" then  -- the given number being the recipe_id
            ui_state.modal_data.message = show.message
            attempt_adding_recipe_line(player, result)
        
        else  -- Otherwise, show the appropriately filtered dialog
            local groups = {}  -- Sort recipes into their respective groups
            for _, recipe in pairs(result) do
                groups[recipe.group.name] = groups[recipe.group.name] or {}
                table.insert(groups[recipe.group.name], recipe)
            end

            ui_state.modal_data.groups = groups
            ui_state.modal_data.recipes = result
            ui_state.modal_data.filters = show.filters

            create_recipe_dialog_structure(player, flow_modal_dialog)
            apply_recipe_filter(player)
        end
    end
end

-- Serves the dual-purpose of determining the appropriate settings for the recipe picker filter and, if there
-- is only one that matches, to return a recipe name that can be added directly without the modal dialog
function run_preliminary_checks(player, product, production_type)
    local force_recipes = player.force.recipes
    local relevant_recipes = {}
    local counts = {
        disabled = 0,
        hidden = 0,
        disabled_hidden = 0
    }
    
    local map = recipe_maps[production_type][product.proto.type][product.proto.name]
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
    local show = { filters={} }
    local user_prefs = get_ui_state(player).recipe_filter_preferences
    local relevant_recipes_count = table_size(relevant_recipes)
    if relevant_recipes_count - counts.disabled - counts.hidden - counts.disabled_hidden > 0 then
        show.filters.disabled = user_prefs.disabled or false
        show.filters.hidden = user_prefs.hidden or false
    elseif relevant_recipes_count - counts.hidden - counts.disabled_hidden > 0 then
        show.filters.disabled = true
        show.filters.hidden = user_prefs.hidden or false
    else
        show.filters.disabled = true
        show.filters.hidden = true
    end
    
    -- Return result, format: return recipe, error-message, show
    if relevant_recipes_count == 0 then
        return nil, {"fp.error_no_relevant_recipe"}, show
    elseif relevant_recipes_count == 1 then
        local chosen_recipe = relevant_recipes[1]
        -- Show hint if adding unresearched recipe (no hints on custom recipes)
        if not chosen_recipe.custom and not force_recipes[chosen_recipe.name].enabled then
            show.message={text={"fp.hint_disabled_recipe"}, type="warning"}
        end
        return chosen_recipe.id, nil, show
    else  -- 2+ relevant recipes
        return relevant_recipes, nil, show
    end
end

-- Creates the unfiltered recipe structure
function create_recipe_dialog_structure(player, flow_modal_dialog)
    local modal_data = get_ui_state(player).modal_data

    -- Filters
    local table_filters = flow_modal_dialog.add{type="table", name="table_filter_conditions", column_count=2}
    table_filters.vertical_centering = false
    table_filters.style.horizontal_spacing = 16

    local label_filters = table_filters.add{type="label", caption={"fp.show"}}
    label_filters.style.top_margin = 2
    label_filters.style.left_margin = 4

    local flow_filter_switches = table_filters.add{type="flow", direction="vertical"}
    ui_util.switch.add_on_off(flow_filter_switches, "recipe_filter_disabled", modal_data.filters.disabled, 
      {"fp.unresearched_recipes"}, nil)
    ui_util.switch.add_on_off(flow_filter_switches, "recipe_filter_hidden", modal_data.filters.hidden,
      {"fp.hidden_recipes"}, nil)

    -- Warning label
    local label_warning = flow_modal_dialog.add{type="label", name="label_warning_message",
      caption={"fp.error_no_recipe_found"}}
    ui_util.set_label_color(label_warning, "red")
    label_warning.style.font = "fp-font-bold-16p"
    label_warning.style.top_margin = 8
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog

    -- Recipes
    local scroll_pane_recipes = flow_modal_dialog.add{type="scroll-pane", name="scroll-pane_recipes", direction="vertical"}
    scroll_pane_recipes.style.horizontally_stretchable = true
    scroll_pane_recipes.style.margin = {8, 2}
    scroll_pane_recipes.style.padding = 2

    local table_recipes = scroll_pane_recipes.add{type="table", name="table_recipes", column_count=2}
    table_recipes.style.horizontal_spacing = 16
    table_recipes.style.vertical_spacing = 8
    
    local force_recipes = player.force.recipes
    -- Go through every group and display their relevant recipes
    for _, group in ipairs(ordered_recipe_groups) do
        local relevant_recipes = modal_data.groups[group.name]

        -- Only actually create this group if it contains any relevant recipes
        if relevant_recipes ~= nil then
            local tooltip = (devmode) and {"", group.localised_name, ("\n" .. group.name)} or group.localised_name
            local group_sprite = table_recipes.add{type="sprite", name=("sprite_group_" .. group.name),
              sprite=("item-group/" .. group.name), tooltip=tooltip}
            group_sprite.style.stretch_image_to_widget_size = true
            group_sprite.style.height = 64
            group_sprite.style.width = 64

            local recipe_table = table_recipes.add{type="table", name=("table_recipe_group_" .. group.name), column_count=8}
            for _, recipe in pairs(relevant_recipes) do
                local button_recipe

                if recipe.custom then  -- can't use choose-elem-buttons for custom recipes
                    button_recipe = recipe_table.add{type="sprite-button", name="fp_button_recipe_pick_"
                    .. recipe.id, sprite=recipe.sprite, tooltip=recipe.tooltip, mouse_button_filter={"left"}}
                else
                    button_recipe = recipe_table.add{type="choose-elem-button", name="fp_button_recipe_pick_"
                      .. recipe.id, elem_type="recipe", recipe=recipe.name, mouse_button_filter={"left"}}
                    button_recipe.locked = true
                end

                -- Determine the appropriate style
                local enabled = (recipe.custom) and true or force_recipes[recipe.name].enabled
                if not enabled then button_recipe.style = "fp_button_icon_medium_disabled" 
                elseif recipe.hidden then button_recipe.style = "fp_button_icon_medium_hidden"
                else button_recipe.style = "fp_button_icon_medium_recipe" end
            end
        end
    end
end

-- Filters the current recipes according to the filters that have been set
function apply_recipe_filter(player)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local table_recipes = flow_modal_dialog["scroll-pane_recipes"]["table_recipes"]
    
    local force_recipes = player.force.recipes
    local ui_state = get_ui_state(player)
    local modal_data = ui_state.modal_data
    local disabled, hidden = modal_data.filters.disabled, modal_data.filters.hidden

    local any_recipe_visible = false
    -- Go through all groups to update every recipe's visibility
    for group_name, recipe_list in pairs(modal_data.groups) do
        local one_recipe_visible = false

        for _, recipe in pairs(recipe_list) do
            local button = table_recipes["table_recipe_group_" .. group_name]["fp_button_recipe_pick_" .. recipe.id]
            local enabled = (recipe.custom) and true or force_recipes[recipe.name].enabled
    
            -- Boolean algebra is reduced here; to understand the intended meaning, take a look at this:
            -- recipe.custom or (not (not disabled and not enabled) and not (not hidden and recipe.hidden))
            button.visible = (recipe.custom or ((disabled or enabled) and (hidden or not recipe.hidden)))

            one_recipe_visible = one_recipe_visible or button.visible
        end
        
        any_recipe_visible = any_recipe_visible or one_recipe_visible
        -- Hide the whole table row if no recipe in it is visible
        table_recipes["sprite_group_" .. group_name].visible = one_recipe_visible
        table_recipes["table_recipe_group_" .. group_name].visible = one_recipe_visible
    end

    -- Show warning if no recipes are shown
    flow_modal_dialog["label_warning_message"].visible = not any_recipe_visible

    -- Determine the scroll-pane height to avoid double scroll-bars in the dialog
    local flow_modal_dialog_height = ui_state.flow_modal_dialog_height
    local warning_label_height = (not any_recipe_visible) and 36 or 0
    local desired_scroll_pane_height = 5 + (table_size(modal_data.groups) * 72)
    flow_modal_dialog["scroll-pane_recipes"].style.height = 
      math.min(desired_scroll_pane_height, flow_modal_dialog_height - 65) - warning_label_height
end


-- Reacts to either the disabled or hidden switches being flicked
function handle_recipe_filter_switch_flick(player, type, state)
    local ui_state = get_ui_state(player)
    local boolean_state = ui_util.switch.convert_to_boolean(state)
    ui_state.modal_data.filters[type] = boolean_state
    
    -- Remember the user selection for this type of filter
    ui_state.recipe_filter_preferences[type] = boolean_state

    apply_recipe_filter(player)
end

-- Tries to add the given recipe to the current floor, then exiting the modal dialog
function attempt_adding_recipe_line(player, recipe_id)
    local ui_state = get_ui_state(player)
    
    local line = Line.init(player, Recipe.init_by_id(recipe_id, ui_state.modal_data.production_type), nil)
    if line == false then
        ui_util.message.enqueue(player, {"fp.error_no_compatible_machine"}, "error", 2)
    else
        Floor.add(ui_state.context.floor, line)
        calculation.update(player, ui_state.context.subfactory, false)

        local message = ui_state.modal_data.message
        if message ~= nil then ui_util.message.enqueue(player, message.text, message.type, 1) end
    end

    exit_modal_dialog(player, "cancel", {})
end
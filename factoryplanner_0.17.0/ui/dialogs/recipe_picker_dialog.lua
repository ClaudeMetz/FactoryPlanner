-- Handles populating the recipe picker dialog
function open_recipe_picker_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local player_table = global.players[player.index]
    local product = player_table.selected_object

    flow_modal_dialog.parent.caption = {"label.add_recipe"}
    flow_modal_dialog.style.bottom_margin = 8

    local search_function = get_search_function(product)

    local recipe, error, show = run_preliminary_checks(player, product.name, search_function)
    if error ~= nil then
        queue_hint_message(player, error)
        exit_modal_dialog(player, "cancel", {})
    else
        -- If 1 relevant, enabled, non-duplicate recipe is found, add it immediately and exit dialog
        if recipe ~= nil then
            local machine = data_util.machines.get_default(player, recipe.category)
            Floor.add(player_table.context.floor, Line.init(recipe, machine))
            update_calculations(player, player_table.context.subfactory)
            exit_modal_dialog(player, "cancel", {})
        
        -- Otherwise, show the appropriately filtered dialog
        else
            picker.refresh_filter_conditions(flow_modal_dialog, {"checkbox.unresearched_recipes"}, {"checkbox.hidden_recipes"})
            picker.refresh_search_bar(flow_modal_dialog, product.name, false)
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_picker_filter_condition_disabled"].state = show.disabled
            flow_modal_dialog["table_filter_conditions"]["fp_checkbox_picker_filter_condition_hidden"].state = show.hidden
            picker.refresh_picker_panel(flow_modal_dialog, "recipe", true)

            picker.select_item_group(player, "recipe", "logistics")
            picker.apply_filter(player, "recipe", true, search_function)
        end
    end
end

-- No additional action needs to be taken when the recipe picker dialog is closed
function close_recipe_picker_dialog(flow_modal_dialog, action, data)
end

-- No conditions needed for the recipe picker dialog
function get_recipe_picker_condition_instructions()
    return {data = {}, conditions = {}}
end

-- Reacts to a picker recipe button being pressed
function handle_picker_recipe_click(player, button)
    local player_table = global.players[player.index]
    local recipe_name = string.gsub(button.name, "fp_sprite%-button_picker_object_", "")
    local recipe = global.all_recipes[player.force.name][recipe_name]
    
    local machine = data_util.machines.get_default(player, recipe.category)
    Floor.add(player_table.context.floor, Line.init(recipe, machine))
    update_calculations(player, player_table.context.subfactory)
    exit_modal_dialog(player, "cancel", {})
end


-- Serves the dual-purpose of setting the filter to include disabled recipes if no enabled ones are found
-- and, if there is only one that matches, to return a recipe name that can be added directly without the modal dialog
-- (This is more efficient than the big filter-loop, which would have to run twice otherwise)
function run_preliminary_checks(player, product_name, search_function)
    -- First determine all relevant recipes and the amount in each category (enabled and hidden)
    local relevant_recipes = {}
    local disabled_recipes_count = 0
    local hidden_recipes_count = 0
    local disabled_hidden_recipes_count = 0
    for _, recipe in pairs(global.all_recipes[player.force.name]) do
        if search_function(recipe, product_name) and recipe.category ~= "handcrafting" then
            table.insert(relevant_recipes, recipe)
            if not recipe.enabled then disabled_recipes_count = disabled_recipes_count + 1 end
            if recipe.hidden then hidden_recipes_count = hidden_recipes_count + 1 end
            if not recipe.enabled and recipe.hidden then disabled_hidden_recipes_count = disabled_hidden_recipes_count + 1 end
        end
    end
    
    -- Set filters to the minimum that still shows at least one recipe if one exists
    -- This is probably stupidly done and could be simplified, I just can't work out how right now
    local show = {disabled = false, hidden = false}
    if (#relevant_recipes - disabled_recipes_count - hidden_recipes_count + disabled_hidden_recipes_count) == 0 then
        show.disabled = true
        if disabled_recipes_count - disabled_hidden_recipes_count == 0 then
            show.hidden = true
        end
    end
    
    -- Return result, format: return recipe, error-message, show
    if #relevant_recipes == 0 then
        return nil, {"label.error_no_relevant_recipe"}, show
    elseif #relevant_recipes == 1 then
        local recipe = relevant_recipes[1]
        if recipe.enabled or not global.players[player.index].settings.show_disabled_recipe then
            return recipe, nil, show
        else
            return nil, nil, show
        end
    else  -- 2+ relevant recipes
        return nil, nil, show
    end
end


-- Returns all recipes
function get_picker_recipes(player)
    return global.all_recipes[player.force.name]
end

-- Generates the tooltip string for the given recipe
function generate_recipe_tooltip(recipe)
    local tooltip = recipe.localised_name
    if recipe.energy ~= nil then 
        tooltip = {"", tooltip, "\n  ", {"tooltip.crafting_time"}, ":  ", recipe.energy}
    end

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


-- Returns the appropriate search function for the given object
function get_search_function(object)
    if object == nil then return nil end
    if object.class == "Product" or object.class == "Ingredient" then return _G["recipe_produces_product"]
    elseif object.class == "Byproduct" then return _G["recipe_consumes_product"] end
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

-- Checks whether given recipe consumes given (by)product
function recipe_consumes_product(recipe, product_name)
    if product_name == "" then return true end
    for _, product in ipairs(recipe.ingredients) do
        if product.name == product_name then
            return true
        end
    end
    return false
end
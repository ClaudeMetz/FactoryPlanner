remote_actions = {
    fnei = {}
}

-- The existance and API-version of these mods does not need to be checked here as
-- this function wouldn't be callable if they weren't valid

-- 'data' needs to contain 'item' (proto) and 'click'
function remote_actions.show_item(remote_action, data)
    remote_actions[remote_action].show_item(data.item, data.click)
end

-- 'data' needs to contain 'recipe' (proto) and 'line_products'
function remote_actions.show_recipe(remote_action, data)
    -- Try to determine a main ingredient for this recipe
    local main_product_name = nil
    if data.recipe.main_product then
        main_product_name = data.recipe.main_product.name
    elseif #data.line_products == 1 then
        main_product_name = data.line_products[1].name
    end
    
    remote_actions[remote_action].show_recipe(data.recipe.name, main_product_name)
end


-- **** FNEI ****
-- This indicates the version of the FNEI remote interface this is compatible with
remote_actions.fnei.version = 2

-- Opens FNEI to show the given item
function remote_actions.fnei.show_item(item_proto, click)
    -- Mirrors FNEI's distinction between left and right clicks
    local action_type = (click == "left") and "craft" or "usage"
    remote.call("fnei", "show_recipe_for_prot", action_type, item_proto.type, item_proto.name)
end

-- Opens FNEI to show the given recipe
function remote_actions.fnei.show_recipe(recipe_name, main_product_name)
    -- If no appropriate context was determined (ie. main_product_name == nil),
    -- FNEI will automatically choose the first ingredient in the list
    remote.call("fnei", "show_recipe", recipe_name, main_product_name)
end
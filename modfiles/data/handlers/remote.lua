remote_actions = {
    util = {},
    fnei = {},
    wiiruf = {},
    recipebook = {}
}

-- **** UTIL ****
-- Returns the alt_action if it is valid, returns the default otherwise
function remote_actions.util.validate_alt_action(alt_action)
    if alt_action ~= nil and global.alt_actions[alt_action] then return alt_action
    else return "none" end
end

-- Returns a table with the names of all valid alt-actions
function remote_actions.util.determine_alt_actions()
    local alt_actions = {["none"] = 1}

    local remote_interfaces = {
        [1] = {internal_name = "fnei", interface_name = "fnei"},
        [2] = {internal_name = "wiiruf", interface_name = "wiiuf"},
        [3] = {internal_name = "recipebook", interface_name = "RecipeBook"}
    }

    local action_index = table_size(alt_actions)
    for _, remote_interface in ipairs(remote_interfaces) do
        if remote.interfaces[remote_interface.interface_name] ~= nil
          and remote.call(remote_interface.interface_name, "version")
          == remote_actions[remote_interface.internal_name].version then

            action_index = action_index + 1
            alt_actions[remote_interface.internal_name] = action_index
        end
    end

    return alt_actions
end


-- The existance and API-version of these mods does not need to be checked here as
-- this function wouldn't be callable if they weren't valid

-- 'data' needs to contain 'item' (proto) and 'click'
function remote_actions.show_item(player, remote_action, data)
    remote_actions[remote_action].show_item(player, data.item, data.click)
end

-- 'data' needs to contain 'recipe' (proto) and 'line_products'
function remote_actions.show_recipe(player, remote_action, data)
    -- Try to determine a main ingredient for this recipe
    local main_product_name = nil
    if data.recipe.main_product then
        main_product_name = data.recipe.main_product.name
    elseif #data.line_products == 1 then
        main_product_name = data.line_products[1].name
    end

    remote_actions[remote_action].show_recipe(player, data.recipe, main_product_name)
end


-- **** FNEI ****
-- This indicates the version of the FNEI remote interface this is compatible with
remote_actions.fnei.version = 2

-- Opens FNEI to show the given item
function remote_actions.fnei.show_item(_, item_proto, click)
    -- Mirrors FNEI's distinction between left and right clicks
    local action_type = (click == "left") and "craft" or "usage"
    remote.call("fnei", "show_recipe_for_prot", action_type, item_proto.type, item_proto.name)
end

-- Opens FNEI to show the given recipe
function remote_actions.fnei.show_recipe(_, recipe_proto, main_product_name)
    -- If no appropriate context was determined (ie. main_product_name == nil),
    -- FNEI will automatically choose the first ingredient in the list
    remote.call("fnei", "show_recipe", recipe_proto.name, main_product_name)
end


-- **** WIIRUF ****
-- This indicates the version of the WIIRUF remote interface this is compatible with
remote_actions.wiiruf.version = 1

-- Opens WIIRUF to show the given item
function remote_actions.wiiruf.show_item(player, item_proto, _)
    remote.call("wiiuf", "open_item", player.index, item_proto.name)
end

-- Opens WIIRUF to show the given recipe
function remote_actions.wiiruf.show_recipe(player, recipe_proto, main_product_name)
    -- WIIRUF always needs an item, so pick the first ingredient if there is no main_product
    main_product_name = main_product_name or recipe_proto.products[1].name
    remote.call("wiiuf", "open_item", player.index, main_product_name, recipe_proto.name)
end


-- **** RecipeBook ****
-- This indicates the version of the RecipeBook remote interface this is compatible with
remote_actions.recipebook.version = 2

local source_data = {mod_name="factoryplanner", gui_name="main_dialog"}

-- Opens RecipeBook to show the given item
function remote_actions.recipebook.show_item(player, item_proto, _)
    remote.call("RecipeBook", "open_gui", player.index, "material", {item_proto.type, item_proto.name}, source_data)
end

-- Opens RecipeBook to show the given recipe
function remote_actions.recipebook.show_recipe(player, recipe_proto, _)
    remote.call("RecipeBook", "open_gui", player.index, "recipe", recipe_proto.name, source_data)
end
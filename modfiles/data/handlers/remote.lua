remote_actions = {
    fnei = {},
    wiiruf = {},
    recipebook = {}
}

-- Maps the internal name of the mod to the interface name they use
local name_interface_map = {fnei="fnei", wiiruf="wiiuf", recipebook="RecipeBook"}

-- The existance of these mods does not need to be checked here as
-- these functions wouldn't be callable if they didn't exist


-- ** LOCAL UTIL **
local function incompatible_version_error(player, remote_action)
    local message = {"fp.error_remote_version_incompatible", {"fp.interface_name_" .. remote_action}}
    titlebar.enqueue_message(player, message, "error", 1, true)
end

-- Makes sure the remote call actually opened another window, show an error message otherwise
local function check_success(player, remote_action, object_type)
    if main_dialog.is_in_focus(player) then
        local message = {"fp.error_remote_lookup_failed", {"fp.pl_" .. object_type, 1},
          {"fp.interface_name_" .. remote_action}}
        titlebar.enqueue_message(player, message, "error", 1, true)
    end
end


-- ** TOP LEVEL **
-- 'data' needs to contain 'item' (proto) and 'click'
function remote_actions.show_item(player, remote_action, data)
    local remote_version = remote.call(name_interface_map[remote_action], "version")
    if remote_version == remote_actions[remote_action].version then
        remote_actions[remote_action].show_item(player, data.item, data.click)
        check_success(player, remote_action, "item")

    else incompatible_version_error(player, remote_action) end
end

-- 'data' needs to contain 'recipe' (proto) and 'line_products'
function remote_actions.show_recipe(player, remote_action, data)
    local remote_version = remote.call(name_interface_map[remote_action], "version")
    if remote_version == remote_actions[remote_action].version then
        -- Try to determine a main ingredient for this recipe
        local main_product_name = nil
        if data.recipe.main_product then
            main_product_name = data.recipe.main_product.name
        elseif #data.line_products == 1 then
            main_product_name = data.line_products[1].name
        end

        remote_actions[remote_action].show_recipe(player, data.recipe, main_product_name)
        check_success(player, remote_action, "recipe")

    else incompatible_version_error(player, remote_action) end
end


-- ** FNEI **
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


-- ** WIIRUF **
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


-- ** RecipeBook **
-- This indicates the version of the RecipeBook remote interface this is compatible with
remote_actions.recipebook.version = 4

-- Opens RecipeBook to show the given item
function remote_actions.recipebook.show_item(player, item_proto, _)
    remote.call("RecipeBook", "open_page", player.index, item_proto.type, item_proto.name)
end

-- Opens RecipeBook to show the given recipe
function remote_actions.recipebook.show_recipe(player, recipe_proto, _)
    remote.call("RecipeBook", "open_page", player.index, "recipe", recipe_proto.name)
end
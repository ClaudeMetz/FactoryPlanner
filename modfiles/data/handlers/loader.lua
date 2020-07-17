-- The loader contains the code that runs on_load, mostly registering
-- conditional events and setting up lua-global tables as a cache
loader = {}
local events, caching = {}, {}


-- ** TOP LEVEL **
-- Runs all the on_load functions
function loader.run()
    events.rate_limiting()

    ordered_recipe_groups = caching.ordered_recipe_groups()
    recipe_maps = {
        produce = caching.recipe_map_from("products"),
        consume = caching.recipe_map_from("ingredients")
    }

    sorted_items = caching.sorted_items()
    identifier_item_map = caching.identifier_item_map()

    item_fuel_map = caching.item_fuel_map()

    module_tier_map = caching.module_tier_map()
end


-- ** EVENTS **
-- Register events related to GUI rate limiting
function events.rate_limiting()
    for _, player_table in pairs(global.players or {}) do
        local last_action = player_table.ui_state.last_action
        if last_action and table_size(last_action) > 0 and last_action.nth_tick ~= nil then
            local rate_limiting_event = ui_util.rate_limiting_events[last_action.event_name]

            script.on_nth_tick(last_action.nth_tick, function(event)
                rate_limiting_event.handler(last_action.element)
                last_action.nth_tick = nil
                last_action.element = nil
                script.on_nth_tick(event.nth_tick, nil)
            end)
        end
    end
end


-- ** CACHING **
-- Returns a list of recipe groups in their proper order
function caching.ordered_recipe_groups()
    group_dict = {}

    -- Make a dict with all recipe groups
    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        if group_dict[recipe.group.name] == nil then
            group_dict[recipe.group.name] = recipe.group
        end
    end

    -- Invert it
    local groups = {}
    for _, group in pairs(group_dict) do
        table.insert(groups, group)
    end

    -- Sort it
    local function sorting_function(a, b)
        if a.order < b.order then
            return true
        elseif a.order > b.order then
            return false
        end
    end

    table.sort(groups, sorting_function)
    return groups
end

-- Maps all items to the recipes that produce or consume them ([item_type][item_name] = {[recipe_id] = true}
function caching.recipe_map_from(item_type)
    local map = {}

    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        for _, item in ipairs(recipe[item_type]) do
            map[item.type] = map[item.type] or {}
            map[item.type][item.name] = map[item.type][item.name] or {}
            map[item.type][item.name][recipe.id] = true
        end
    end

    return map
end


-- Generates a list of all items, sorted for display in the picker
function caching.sorted_items()
    -- Combines item and fluid prototypes into an unsorted number-indexed array
    local items = {}
    local all_items = global.all_items
    for _, type in pairs({"item", "fluid"}) do
        for _, item in pairs(all_items.types[all_items.map[type]].items) do
            -- Silly checks needed here for migration purposes
            if item.group.valid and item.subgroup.valid then table.insert(items, item) end
        end
    end

    -- Sorts the objects according to their group, subgroup and order
    local function sorting_function(a, b)
        if a.group.order < b.group.order then return true
        elseif a.group.order > b.group.order then return false
        elseif a.subgroup.order < b.subgroup.order then return true
        elseif a.subgroup.order > b.subgroup.order then return false
        elseif a.order < b.order then return true
        elseif a.order > b.order then return false end
    end

    table.sort(items, sorting_function)
    return items
end

-- Generates a table mapping item identifier to their prototypes
function caching.identifier_item_map()
    local map = {}

    local all_items = global.all_items
    for _, type in pairs({"item", "fluid"}) do
        for _, item in pairs(all_items.types[all_items.map[type]].items) do
            -- Identifier existance-check for migration reasons
            if item.identifier ~= nil then map[item.identifier] = item end
        end
    end

    return map
end


-- Maps every fuel_proto to a (item[type][name] -> fuel_proto)-map
-- This is possible because every fuel can only be in one category at a time
function caching.item_fuel_map()
    local map = {}

    if not global.all_fuels.categories then return end
    for _, category in pairs(global.all_fuels.categories) do
        for _, fuel_proto in pairs(category.fuels) do
            map[fuel_proto.type] = map[fuel_proto.type] or {}
            map[fuel_proto.type][fuel_proto.name] = fuel_proto
        end
    end

    return map
end


-- Generates a table containing all module per category, ordered by tier
function caching.module_tier_map()
    local map = {}

    if not global.all_modules then return end
    for _, category in pairs(global.all_modules.categories) do
        map[category.id] = {}
        for _, module in pairs(category.modules) do
            map[category.id][module.tier] = module
        end
    end

    return map
end
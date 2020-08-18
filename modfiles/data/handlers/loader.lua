-- The loader contains the code that runs on_load, pre-caching some data structures that are needed later
loader = {}

-- ** LOCAL UTIL **
-- Returns a list of recipe groups in their proper order
local function ordered_recipe_groups()
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
        if a.order < b.order then return true
        elseif a.order > b.order then return false end
    end
    table.sort(groups, sorting_function)

    return groups
end

-- Maps all items to the recipes that produce or consume them ([item_type][item_name] = {[recipe_id] = true}
local function recipe_map_from(item_type)
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
local function sorted_items()
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
local function identifier_item_map()
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


-- Generates a table containing all modules per category, ordered by tier
local function module_tier_map()
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

-- Generates a table mapping modules to their prototype by name
local function module_name_map()
    local map = {}

    if not global.all_modules then return end
    for _, category in pairs(global.all_modules.categories) do
        for _, module in pairs(category.modules) do
            map[module.name] = module
        end
    end

    return map
end


local attribute_generators = {}

function attribute_generators.beacons(beacon)
    return {"", {"fp.module_slots"}, ": " .. beacon.module_limit .. "\n",
           {"fp.effectivity"}, ": " .. (beacon.effectivity * 100) .. "%\n",
           {"fp.energy_consumption"}, ": ", ui_util.format_SI_value(beacon.energy_usage, "W", 3)}
end

function attribute_generators.fuels(fuel)
    return {"", {"fp.fuel_value"}, ": ", ui_util.format_SI_value(fuel.fuel_value, "J", 3), "\n",
           {"fp.emissions_multiplier"}, ": " .. fuel.emissions_multiplier}
end

function attribute_generators.belts(belt)
    return {"", {"fp.throughput"}, ": " .. belt.throughput .. " ", {"fp.items"}, "/", {"fp.unit_second"}}
end

function attribute_generators.machines(machine)
    local energy_usage = machine.energy_usage * 60
    return {"", {"fp.crafting_speed"}, ": " .. ui_util.format_number(machine.speed, 4) .. "\n",
           {"fp.energy_consumption"}, ": ", ui_util.format_SI_value(energy_usage, "W", 3), "\n",
           {"fp.cpollution"}, ": ", ui_util.format_SI_value(energy_usage * machine.emissions * 60, "P/m", 3), "\n",
           {"fp.module_slots"}, ": " .. machine.module_limit}
end

-- Generates the attribute strings for some types of prototypes
local function prototype_attributes()
    local relevant_prototypes = {"belts", "beacons", "fuels", "machines"}
    local attributes = {}

    for _, type in pairs(relevant_prototypes) do
        local all_prototypes = global["all_" .. type]
        if not all_prototypes or not all_prototypes.structure_type then return end

        local generator_function = attribute_generators[type]

        attributes[type] = {}
        local attribute_type = attributes[type]

        if all_prototypes.structure_type == "simple" then
            for proto_id, prototype in pairs(all_prototypes[type]) do
                attribute_type[proto_id] = generator_function(prototype)
            end

        else  -- structure_type == "complex"
            for category_id, category in pairs(all_prototypes.categories) do
                attribute_type[category_id] = {}
                local attribute_category = attribute_type[category_id]

                for proto_id, prototype in pairs(category[type]) do
                    attribute_category[proto_id] = generator_function(prototype)
                end
            end
        end
    end

    return attributes
end


-- ** TOP LEVEL **
-- Creates some lua-global tables for convenience and performance
function loader.run()
    local freeplay = remote.interfaces["freeplay"]
    if DEVMODE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    ORDERED_RECIPE_GROUPS = ordered_recipe_groups()
    RECIPE_MAPS = {
        produce = recipe_map_from("products"),
        consume = recipe_map_from("ingredients")
    }

    SORTED_ITEMS = sorted_items()
    IDENTIFIER_ITEM_MAP = identifier_item_map()

    MODULE_TIER_MAP = module_tier_map()
    MODULE_NAME_MAP = module_name_map()

    PROTOTYPE_ATTRIBUTES = prototype_attributes()
end
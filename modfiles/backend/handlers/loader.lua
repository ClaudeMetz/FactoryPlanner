-- The loader contains the code that runs on_load, pre-caching some data structures that are needed later
local loader = {}

---@alias RecipeMap { [ItemCategoryID]: { [ItemID]: { [RecipeID]: true } } }
---@alias ItemCategoryID integer
---@alias ItemID integer
---@alias RecipeID integer

---@alias ModuleMap { [string]: FPModulePrototype }

-- ** LOCAL UTIL **
-- Returns a list of recipe groups in their proper order
---@return ItemGroup[]
local function ordered_recipe_groups()
    -- Make a dict with all recipe groups
    local group_dict = {}  ---@type { [string]: ItemGroup }
    for _, recipe in pairs(storage.prototypes.recipes) do
        if group_dict[recipe.group.name] == nil then
            group_dict[recipe.group.name] = recipe.group
        end
    end

    -- Invert it
    local groups = {}  ---@type ItemGroup[]
    for _, group in pairs(group_dict) do
        table.insert(groups, group)
    end

    -- Sort it
    ---@param a ItemGroup
    ---@param b ItemGroup
    ---@return boolean
    local function sorting_function(a, b)
        if a.order < b.order then return true
        elseif a.order > b.order then return false end
        return false
    end
    table.sort(groups, sorting_function)

    return groups
end

-- Maps all items to the recipes that produce or consume them ([item_type][item_name] = {[recipe_id] = true}
---@param item_type "products" | "ingredients"
---@return RecipeMap
local function recipe_map_from(item_type)
    local map = {}  ---@type RecipeMap

    for _, recipe in pairs(storage.prototypes.recipes) do
        for _, item in ipairs(recipe[item_type]) do
            local item_proto = prototyper.util.find("items", item.name, item.type)  ---@cast item_proto -nil
            map[item_proto.category_id] = map[item_proto.category_id] or {}
            map[item_proto.category_id][item_proto.id] = map[item_proto.category_id][item_proto.id] or {}
            map[item_proto.category_id][item_proto.id][recipe.id] = true
        end
    end

    return map
end


-- Generates a list of all items, sorted for display in the picker
---@return FPItemPrototype[]
local function sorted_items()
    local items = {}

    for _, type in pairs{"item", "fluid", "entity"} do
        for _, item in pairs(prototyper.util.find("items", nil, type).members) do
            table.insert(items, item)
        end
    end

    -- Sorts the objects according to their group, subgroup and order
    ---@param a FPItemPrototype
    ---@param b FPItemPrototype
    ---@return boolean
    local function sorting_function(a, b)
        if a.group.order < b.group.order then return true
        elseif a.group.order > b.group.order then return false
        elseif a.subgroup.order < b.subgroup.order then return true
        elseif a.subgroup.order > b.subgroup.order then return false
        elseif a.order < b.order then return true
        elseif a.order > b.order then return false end
        return false
    end

    table.sort(items, sorting_function)
    return items
end


---@alias MappedPrototypes<T> { [string]: T }
---@alias MappedPrototypesWithCategory<T> { [string]: { id: integer, name: string, members: { [string]: T } } }
---@alias MappedCategory { id: integer, name: string, members: { [string]: table } }

---@class PrototypeMaps: { [DataType]: table }
---@field machines MappedPrototypesWithCategory<FPMachinePrototype>
---@field recipes MappedPrototypes<FPRecipePrototype>
---@field items MappedPrototypesWithCategory<FPItemPrototype>
---@field fuels MappedPrototypesWithCategory<FPFuelPrototype>
---@field belts MappedPrototypes<FPBeltPrototype>
---@field wagons MappedPrototypesWithCategory<FPWagonPrototype>
---@field modules MappedPrototypesWithCategory<FPModulePrototype>
---@field beacons MappedPrototypes<FPBeaconPrototype>
---@field locations MappedPrototypes<FPLocationPrototype>
---@field qualities MappedPrototypes<FPQualityPrototype>

---@param data_types { [DataType]: boolean }
---@return PrototypeMaps
local function prototype_maps(data_types)
    local maps = {}  ---@type PrototypeMaps

    for data_type, has_categories in pairs(data_types) do
        local map = {}

        if not has_categories then
            ---@cast map MappedPrototypes<FPPrototype>

            ---@type IndexedPrototypes<FPPrototype>
            local prototypes = storage.prototypes[data_type]

            for _, prototype in pairs(prototypes) do
                map[prototype.name] = prototype
            end
        else
            ---@cast map MappedPrototypesWithCategory<FPPrototypeWithCategory>

            ---@type IndexedPrototypesWithCategory<FPPrototypeWithCategory>
            local prototypes = storage.prototypes[data_type]

            for _, category in pairs(prototypes) do
                map[category.name] = { name=category.name, id=category.id, members={} }
                for _, prototype in pairs(category.members) do
                    map[category.name].members[prototype.name] = prototype
                end
            end
        end

        maps[data_type] = map
    end

    return maps
end


-- Generates a table mapping modules to their prototype by name
---@return ModuleMap
local function module_name_map()
    local map = {}  ---@type ModuleMap

    for _, category in pairs(storage.prototypes.modules) do
        for _, module in pairs(category.members) do
            map[module.name] = module
        end
    end

    return map
end



local function generate_object_index()
    OBJECT_INDEX = {}  ---@type { [integer]: Object}
    for _, player_table in pairs(storage.players) do
        if not player_table.realm then return end  -- migration issue mitigation
        player_table.realm:index()  -- recursively indexes all objects
    end

    if storage.tutorial_factory then
        storage.tutorial_factory:index()
    end
end


-- ** TOP LEVEL **
---@param skip_check boolean Whether the mod version check is skipped
function loader.run(skip_check)
    if not skip_check and script.active_mods["factoryplanner"] ~= storage.installed_mods["factoryplanner"] then
        return  -- if the mod version changed, the loader will be re-run after migration anyways
    end

    util.nth_tick.register_all()
    generate_object_index()

    PROTOTYPE_MAPS = prototype_maps(prototyper.data_types)
    MODULE_NAME_MAP = module_name_map()

    ORDERED_RECIPE_GROUPS = ordered_recipe_groups()
    RECIPE_MAPS = {
        produce = recipe_map_from("products"),
        consume = recipe_map_from("ingredients")
    }

    SORTED_ITEMS = sorted_items()
end

return loader

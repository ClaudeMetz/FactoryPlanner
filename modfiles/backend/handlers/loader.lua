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
    for _, recipe in pairs(global.prototypes.recipes) do
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

    for _, recipe in pairs(global.prototypes.recipes) do
        for _, item in ipairs(recipe[item_type] --[[@as FormattedRecipeItem[] ]]) do
            local item_proto = prototyper.util.find_prototype("items", item.name, item.type)  ---@cast item_proto -nil
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

    for _, type in pairs{"item", "fluid"} do
        for _, item in pairs(PROTOTYPE_MAPS.items[type].members) do
            -- Silly checks needed here for migration purposes
            if item.group.valid and item.subgroup.valid then table.insert(items, item) end
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


-- Generates a table mapping modules to their prototype by name
---@return ModuleMap
local function module_name_map()
    local map = {}  ---@type ModuleMap

    for _, category in pairs(global.prototypes.modules) do
        for _, module in pairs(category.members) do
            map[module.name] = module
        end
    end

    return map
end


local attribute_generators = {}  ---@type { [string]: fun(proto: AnyFPPrototype): LocalisedString }

---@param belt FPBeltPrototype
---@return LocalisedString
function attribute_generators.belts(belt)
    local throughput_string = {"", belt.throughput .. " ", {"fp.pl_item", 2}, "/", {"fp.unit_second"}}
    return {"fp.attribute_line", {"fp.throughput"}, throughput_string}
end

---@param beacon FPBeaconPrototype
---@return LocalisedString
function attribute_generators.beacons(beacon)
    return {"", {"fp.attribute_line", {"fp.module_slots"}, beacon.module_limit},
           {"fp.attribute_line", {"fp.effectivity"}, (beacon.effectivity * 100) .. "%"},
           {"fp.attribute_line", {"fp.u_power"}, util.format.SI_value(beacon.energy_usage * 60, "W", 3)}}
end

---@param wagon FPWagonPrototype
---@return LocalisedString
function attribute_generators.wagons(wagon)
    local storage_unit = (wagon.category == "cargo-wagon") and {"fp.pl_stack", wagon.storage} or {"fp.l_fluid"}
    return {"fp.attribute_line", {"fp.storage"}, {"", util.format.number(wagon.storage, 3) .. " ", storage_unit}}
end

---@param fuel FPFuelPrototype
---@return LocalisedString
function attribute_generators.fuels(fuel)
    return {"", {"fp.attribute_line", {"fp.fuel_value"}, util.format.SI_value(fuel.fuel_value, "J", 3)},
           {"fp.attribute_line", {"fp.emissions_multiplier"}, fuel.emissions_multiplier}}
end

---@param machine FPMachinePrototype
---@return LocalisedString
function attribute_generators.machines(machine)
    return {"", {"fp.attribute_line", {"fp.crafting_speed"}, util.format.number(machine.speed, 3)},
           {"fp.attribute_line", {"fp.u_power"}, util.format.SI_value(machine.energy_usage * 60, "W", 3)},
           {"fp.attribute_line", {"fp.module_slots"}, machine.module_limit}}
end


---@alias PrototypeAttributes { [DataType]: { [integer]: LocalisedString } }
---@alias PrototypeAttributesWithCategory { [DataType]: { [integer]: { [integer]: LocalisedString } } }

-- Generates the attribute strings for some types of prototypes
---@return PrototypeAttributes | PrototypeAttributesWithCategory
local function prototype_attributes()
    local relevant_prototypes = {"belts", "beacons", "wagons", "fuels", "machines"}
    local attributes = {}  ---@type PrototypeAttributes | PrototypeAttributesWithCategory

    for _, data_type in pairs(relevant_prototypes) do
        local prototypes = global.prototypes[data_type]  ---@type AnyIndexedPrototypes
        local generator_function = attribute_generators[data_type]

        attributes[data_type] = {}
        if prototyper.data_types[data_type] == false then
            ---@cast prototypes IndexedPrototypes<FPPrototype>
            ---@cast attributes PrototypeAttributes

            for proto_id, prototype in pairs(prototypes) do
                attributes[data_type][proto_id] = generator_function(prototype)
            end
        else
            ---@cast prototypes IndexedPrototypesWithCategory<FPPrototypeWithCategory>
            ---@cast attributes PrototypeAttributesWithCategory

            for category_id, category in pairs(prototypes) do
                attributes[data_type][category_id] = {}
                local attribute_category = attributes[data_type][category_id]

                for proto_id, prototype in pairs(category.members) do
                    attribute_category[proto_id] = generator_function(prototype)
                end
            end
        end
    end

    return attributes
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

---@param data_types { [DataType]: boolean }
---@return PrototypeMaps
local function prototype_maps(data_types)
    local maps = {}  ---@type PrototypeMaps

    for data_type, has_categories in pairs(data_types) do
        local map = {}

        if not has_categories then
            ---@cast map MappedPrototypes<FPPrototype>

            ---@type IndexedPrototypes<FPPrototype>
            local prototypes = global.prototypes[data_type]

            for _, prototype in pairs(prototypes) do
                map[prototype.name] = prototype
            end
        else
            ---@cast map MappedPrototypesWithCategory<FPPrototypeWithCategory>

            ---@type IndexedPrototypesWithCategory<FPPrototypeWithCategory>
            local prototypes = global.prototypes[data_type]

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


local function generate_object_index()
    OBJECT_INDEX = {}
    for _, player_table in pairs(global.players) do
        local realm = player_table.realm
        if not player_table.realm then return {} end  -- migration issue mitigation
        realm:index()  -- recursively indexes all objects
    end

    if global.tutorial_factory then
        global.tutorial_factory:index()
    end
end


-- ** TOP LEVEL **
---@param skip_check boolean Whether the mod version check is skipped
function loader.run(skip_check)
    if not skip_check and script.active_mods["factoryplanner"] ~= global.installed_mods["factoryplanner"] then
        return  -- if the mod version changed, the loader will be re-run after migration anyways
    end

    util.nth_tick.register_all()
    generate_object_index()

    PROTOTYPE_MAPS = prototype_maps(prototyper.data_types)
    PROTOTYPE_ATTRIBUTES = prototype_attributes()

    ORDERED_RECIPE_GROUPS = ordered_recipe_groups()
    RECIPE_MAPS = {
        produce = recipe_map_from("products"),
        consume = recipe_map_from("ingredients")
    }

    SORTED_ITEMS = sorted_items()
    MODULE_NAME_MAP = module_name_map()
end

return loader

-- The loader contains the code that runs on_load, pre-caching some data structures that are needed later
local loader = {}

---@alias RecipeMap table<integer, table<integer, table<integer, true>>>
---@alias TemperatureMap table<string, FPItemPrototype[]>
---@alias ModuleMap table<string, FPModulePrototype>

-- ** LOCAL UTIL **
-- Returns a list of recipe groups in their proper order
---@return ItemGroup[]
local function ordered_recipe_groups()
    -- Make a dict with all recipe groups
    local group_dict = {}  ---@type table<string, ItemGroup>
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
    -- There is always only 3 categories (item, fluid, entity)
    local map = {[1] = {}, [2] = {}, [3] = {}}  ---@type RecipeMap

    ---@param item_proto FPItemPrototype
    ---@param recipe_id integer
    local function add(item_proto, recipe_id)
        local category = map[item_proto.category_id]
        category[item_proto.id] = category[item_proto.id] or {}
        category[item_proto.id][recipe_id] = true
    end

    for _, recipe in pairs(storage.prototypes.recipes) do
        for _, item in ipairs(recipe[item_type]) do
            if item_type == "ingredients" and item.type == "fluid" then
                local min_temp = item.minimum_temperature
                local max_temp = item.maximum_temperature
                for _, fluid_proto in pairs(TEMPERATURE_MAP[item.name] or {}) do
                    if (not min_temp or min_temp <= fluid_proto.temperature) and
                            (not max_temp or max_temp >= fluid_proto.temperature) then
                        add(fluid_proto, recipe.id)
                    end
                end
            else
                local item_proto = prototyper.util.find("items", item.name, item.type)
                add(item_proto--[[@as FPItemPrototype]], recipe.id)
            end
        end
    end

    return map
end


-- Generates a list of all items, sorted for display in the picker
---@return FPItemPrototype[]
local function sorted_items()
    local items = {}

    for _, type in pairs{"item", "fluid", "entity"} do
        local category = prototyper.util.find("items", nil, type)  ---@as NamedCategory<FPItemPrototype>
        for _, item in pairs(category.members--[[@cast -nil]]) do
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
        elseif a.order > b.order then return false
        elseif (a.temperature or 0) < (b.temperature or 0) then return true
        elseif (a.temperature or 0) > (b.temperature or 0) then return false end
        return false
    end

    table.sort(items, sorting_function)
    return items
end


---@return TemperatureMap
local function temperature_map()
    local map = {}  ---@type TemperatureMap

    for name, fluid_proto in pairs(PROTOTYPE_MAPS.items.fluid.members) do
        if fluid_proto.temperature ~= nil then
            local base_name = fluid_proto.base_name
            if not map[base_name] then map[base_name] = {} end
            table.insert(map[base_name], fluid_proto)
        end
    end

    ---@param a FPItemPrototype
    ---@param b FPItemPrototype
    ---@return boolean
    local function sorting_function(a, b)
        if a.temperature < b.temperature then return true
        elseif a.temperature > b.temperature then return false end
        return false
    end

    for _, list in pairs(map) do
        table.sort(list, sorting_function)
    end

    return map
end


---@alias MappedPrototypes<T> table<string, T>
---@alias MappedPrototypesWithCategory<T> table<string, MappedCategory<T>>
---@alias MappedCategory<T> { id: integer, name: string, members: MappedPrototypes<T> }

---@class PrototypeMaps
---@field recipes MappedPrototypes<FPRecipePrototype>
---@field items MappedPrototypesWithCategory<FPItemPrototype>
---@field machines MappedPrototypesWithCategory<FPMachinePrototype>
---@field fuels MappedPrototypesWithCategory<FPFuelPrototype>
---@field belts MappedPrototypes<FPBeltPrototype>
---@field pumps MappedPrototypes<FPPumpPrototype>
---@field silos MappedPrototypes<FPSiloPrototype>
---@field wagons MappedPrototypesWithCategory<FPWagonPrototype>
---@field modules MappedPrototypesWithCategory<FPModulePrototype>
---@field beacons MappedPrototypes<FPBeaconPrototype>
---@field locations MappedPrototypes<FPLocationPrototype>
---@field qualities MappedPrototypes<FPQualityPrototype>

---@param data_types table<DataType, boolean>
---@return PrototypeMaps
local function prototype_maps(data_types)
    local maps = {}  ---@type table<DataType, table>

    for data_type, has_categories in pairs(data_types) do
        local map = {}

        local prototypes = storage.prototypes[data_type]  ---@type AnyIndexedPrototypes

        if not has_categories then
            ---@cast map MappedPrototypes<FPPrototype>
            ---@cast prototypes IndexedPrototypes<FPPrototype>

            for _, prototype in pairs(prototypes) do
                map[prototype.name] = prototype
            end
        else
            ---@cast map MappedPrototypesWithCategory<FPPrototypeWithCategory>
            ---@cast prototypes IndexedPrototypesWithCategory<FPPrototypeWithCategory>

            for _, category in pairs(prototypes) do
                map[category.name] = { name=category.name, id=category.id, members={} }
                for _, prototype in pairs(category.members) do
                    map[category.name].members[prototype.name] = prototype
                end
            end
        end

        maps[data_type] = map
    end

    return maps  ---@as PrototypeMaps
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


---@return table<string, boolean>
local function generate_productivity_recipes()
    local productivity_recipes = {}
    for _, recipe in pairs(storage.prototypes.recipes) do
        if recipe.productivity_recipe then
            productivity_recipes[recipe.productivity_recipe] = true
        end
    end
    return productivity_recipes
end


-- Determines the tick count and energy consumption of launching a rocket for the given silo
-- This does not take into account the full launch cycle, but instead calculates the fastest
-- possible one, using the quick follow-up rocket mechanic, as that's the limiting case.
-- The tick results are seemingly off by a handful of ticks, but it's close enough.
-- Power consumption results might be low by 10% or so from light empirical testing.
---@param silo_proto LuaEntityPrototype
---@param quality_level integer
---@return LauncherDataSet
local function determine_launch_data(silo_proto, quality_level)
    local power = silo_proto.active_energy_usage  ---@as double
    local rocket_proto = silo_proto.rocket_entity_prototype  ---@as LuaEntityPrototype

    local rising_speed = rocket_proto.rising_speed--[[@cast -nil]] * (1 +
        silo_proto.rocket_rising_speed_modifier_per_quality_level--[[@cast -nil]] * quality_level)
    local engine_starting_speed = rocket_proto.engine_starting_speed--[[@cast -nil]] * (1 +
        silo_proto.rocket_engine_starting_speed_modifier_per_quality_level--[[@cast -nil]] * quality_level)
    -- Arms speed not accessible in the API, so we have to use what vanilla does: 0.3
    local arms_speed = 0.3 * (1 + silo_proto.arms_speed_modifier_per_quality_level--[[@cast -nil]] * quality_level)

    local frame_count = 32  -- not accessible in the API, use vanilla value
    local arm_move_offset = rising_speed * frame_count * (1 / arms_speed)

    -- Cycle starts here
    local launch_ticks, energy_usage = 0, 0  ---@type number, number

    local doors_opened = 1
    launch_ticks = launch_ticks + doors_opened

    local rocket_rising_threshold = 1 - silo_proto.rocket_quick_relaunch_start_offset--[[@as double]] - arm_move_offset
    local rocket_rising = rocket_rising_threshold / rising_speed
    launch_ticks = launch_ticks + rocket_rising
    energy_usage = energy_usage + (rocket_rising * power)

    local arms_advance = arm_move_offset / rising_speed
    launch_ticks = launch_ticks + arms_advance
    energy_usage = energy_usage + (arms_advance * power)

    local launch_starting = 1
    launch_ticks = launch_ticks + launch_starting

    local launch_started = silo_proto.launch_wait_time--[[@as uint8]]
    launch_ticks = launch_ticks + launch_started

    local engine_starting = 1 / engine_starting_speed
    launch_ticks = launch_ticks + engine_starting
    energy_usage = energy_usage + (engine_starting * power)

    local arms_retract = arm_move_offset / rising_speed
    launch_ticks = launch_ticks + arms_retract
    energy_usage = energy_usage + (arms_retract * power)

    local rocket_flight_threshold = 0.1  -- hardcoded in the game files
    -- I'm not exactly sure why this behaves as the game code does, *but it do*
    local rocket_flying = math.log(1 + rocket_flight_threshold * rocket_proto.flying_acceleration--[[@as double]]
        / rocket_proto.flying_speed--[[@as double]]) / math.log(1 + rocket_proto.flying_acceleration--[[@as double]])
    launch_ticks = launch_ticks + rocket_flying - arms_retract

    return {speed = 1 / (launch_ticks / 60), energy_usage = energy_usage / launch_ticks}
end

---@alias LauncherData table<string, table<string, LauncherDataSet>>
---@alias LauncherDataSet {speed: number, energy_usage: number}

-- Pre-calculates all silo-quality combination speeds and energy usages
---@return LauncherData
local function generate_launcher_data()
    local data = {}  ---@type LauncherData

    local silo_filter = {{filter="type", type="rocket-silo"},
        {filter="hidden", invert=true, mode="and"}}
    for silo_name, silo_proto in pairs(prototypes.get_entity_filtered(silo_filter)) do
        data[silo_name] = {}
        for _, quality_proto in pairs(storage.prototypes.qualities) do
            local dataset = determine_launch_data(silo_proto, quality_proto.level)
            data[silo_name][quality_proto.name] = dataset
        end
    end

    return data
end


-- ** TOP LEVEL **
function loader.run()
    PROTOTYPE_MAPS = prototype_maps(prototyper.data_types)
    MODULE_NAME_MAP = module_name_map()

    SORTED_ITEMS = sorted_items()
    TEMPERATURE_MAP = temperature_map()

    ORDERED_RECIPE_GROUPS = ordered_recipe_groups()
    RECIPE_MAPS = {
        produce = recipe_map_from("products"),
        consume = recipe_map_from("ingredients")
    }

    PRODUCTIVITY_RECIPES = generate_productivity_recipes()
    LAUNCHER_DATA = generate_launcher_data()

    MULTIPLE_PLANETS = #storage.prototypes.locations > 1
end

return loader

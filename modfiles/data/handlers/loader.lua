-- The loader contains the code that runs on_load, pre-caching some data structures that are needed later
local loader = {}

-- ** LOCAL UTIL **
-- Returns a list of recipe groups in their proper order
local function ordered_recipe_groups()
    local group_dict = {}

    -- Make a dict with all recipe groups
    for _, recipe in pairs(global.prototypes.recipes) do
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

    for _, recipe in pairs(global.prototypes.recipes) do
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
    local items = {}

    for _, type in pairs{"item", "fluid"} do
        for _, item in pairs(PROTOTYPE_MAPS.items[type].members) do
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


-- Generates a table mapping modules to their prototype by name
local function module_name_map()
    local map = {}

    for _, category in pairs(global.prototypes.modules) do
        for _, module in pairs(category.members) do
            map[module.name] = module
        end
    end

    return map
end


local attribute_generators = {}

function attribute_generators.belts(belt)
    local throughput_string = {"", belt.throughput .. " ", {"fp.pl_item", 2}, "/", {"fp.unit_second"}}
    return {"fp.attribute_line", {"fp.throughput"}, throughput_string}
end

function attribute_generators.beacons(beacon)
    return {"", {"fp.attribute_line", {"fp.module_slots"}, beacon.module_limit},
           {"fp.attribute_line", {"fp.effectivity"}, (beacon.effectivity * 100) .. "%"},
           {"fp.attribute_line", {"fp.energy_consumption"}, ui_util.format_SI_value(beacon.energy_usage * 60, "W", 3)}}
end

function attribute_generators.wagons(wagon)
    local storage_unit = (wagon.category == "cargo-wagon") and {"fp.pl_stack", wagon.storage} or {"fp.l_fluid"}
    return {"fp.attribute_line", {"fp.storage"}, {"", ui_util.format_number(wagon.storage, 3) .. " ", storage_unit}}
end

function attribute_generators.fuels(fuel)
    return {"", {"fp.attribute_line", {"fp.fuel_value"}, ui_util.format_SI_value(fuel.fuel_value, "J", 3)},
           {"fp.attribute_line", {"fp.emissions_multiplier"}, fuel.emissions_multiplier}}
end

function attribute_generators.machines(machine)
    local pollution = machine.energy_usage * (machine.emissions * 60) * 60
    return {"", {"fp.attribute_line", {"fp.crafting_speed"}, ui_util.format_number(machine.speed, 3)},
           {"fp.attribute_line", {"fp.energy_consumption"}, ui_util.format_SI_value(machine.energy_usage * 60, "W", 3)},
           {"fp.attribute_line", {"fp.pollution"}, {"", ui_util.format_SI_value(pollution, "P/m", 3)}},
           {"fp.attribute_line", {"fp.module_slots"}, machine.module_limit}}
end

-- Generates the attribute strings for some types of prototypes
local function prototype_attributes()
    local relevant_prototypes = {"belts", "beacons", "wagons", "fuels", "machines"}
    local attributes = {}

    for _, data_type in pairs(relevant_prototypes) do
        local prototypes = global.prototypes[data_type]
        local generator_function = attribute_generators[data_type]

        attributes[data_type] = {}
        if prototyper.data_types[data_type] == false then
            for proto_id, prototype in pairs(prototypes) do
                attributes[data_type][proto_id] = generator_function(prototype)
            end
        else
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


local function prototype_maps(data_types)
    local maps = {}
    for data_type, has_categories in pairs(data_types) do
        local prototypes = global.prototypes[data_type]
        local map = {}

        if not has_categories then
            for _, prototype in pairs(prototypes) do
                map[prototype.name] = prototype
            end
        else
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


-- ** TOP LEVEL **
function loader.run(skip_check)
    -- If the mod version changed, this'll be re-run after migration anyways
    if not skip_check and script.active_mods["factoryplanner"] ~= global.mod_version then return end

    data_util.nth_tick.register_all()

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

data_util = {
    machine = {},
    base_data = {}
}

-- **** MACHINES ****
-- Changes the preferred machine for the given category
function data_util.machine.set_default(player, category_id, machine_id)
    local preferences = get_preferences(player)
    local machine = global.all_machines.categories[category_id].machines[machine_id]
    preferences.default_machines.categories[category_id] = machine
    preferences.default_machines.map[machine.name] = category_id
end

-- Returns the default machine for the given category
function data_util.machine.get_default(player, category_name)
    local category_id = global.all_machines.map[category_name]
    return get_preferences(player).default_machines.categories[category_id]
end


-- **** BASE DATA ****
-- Creates the default structure for default_machines
function data_util.base_data.default_machines(table)
    local default_machines = {categories = {}, map = {}}
    for category_id, category in pairs(table.all_machines.categories) do
        default_machines.categories[category_id] = category.machines[1]
        default_machines.map[category.name] = category_id
    end
    return default_machines
end

-- Returns the default preferred belt
function data_util.base_data.preferred_belt(table)
    return table.all_belts.belts[1]
end

-- Returns the default preferred fuel (tries to choose coal)
function data_util.base_data.preferred_fuel(table)
    local fuels = table.all_fuels
    if fuels.map["coal"] then
        return fuels.fuels[fuels.map["coal"]]
    else
        return fuels.fuels[1]
    end
end

-- Returns the default preferred beacon
function data_util.base_data.preferred_beacon(table)
    return table.all_beacons.beacons[1]
end


-- **** MISC ****
-- Updates validity of every class specified by the classes parameter
function data_util.run_validation_updates(parent, classes)
    local valid = true
    for type, class in pairs(classes) do
        if not Collection.update_validity(parent[type], class) then
            valid = false
        end
    end
    return valid
end

-- Tries to repair every specified class, deletes them if this is unsuccessfull
function data_util.run_invalid_dataset_repair(player, parent, classes)
    for type, class in pairs(classes) do
        Collection.repair_invalid_datasets(parent[type], player, class, parent)
    end
end
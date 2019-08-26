loader = {
    util = {},
    machines = {},
    belts = {},
    fuels = {},
    beacons = {}
}

-- The purpose of a loader is to recreate the global tables containing all relevant data types.
-- It also updates the factories to the new id's of all those datasets.
-- Its purpose is to not lose any data, so if a dataset of a factory-dataset doesn't exist anymore
-- in the newly loaded global tables, it saves the name in string-form instead and makes the
-- concerned factory-dataset invalid. This accomplishes that invalid data is only permanently
-- removed when the user tells the subfactory to repair itself, giving him a chance to re-add the
-- missing mods. It is also a better separation of responsibilities and avoids some redundant code.

-- (Load order is important here: machines->recipes->items->fuels)
local data_types = {"machines", "recipes", "items", "fuels", "belts", "modules", "beacons"}

-- Generates the new data and mapping_tables and saves them to lua-globals
function loader.setup()
    new = {}
    for _, data_type in ipairs(data_types) do
        new["all_" .. data_type] = generator["all_" .. data_type]()
    end
end

-- Updates the relevant data of the given player to fit the new data
function loader.run(player_table)
    -- Then, update the default/preferred datasets
    for _, data_type in ipairs(data_types) do
        local f = loader[data_type]
        if f ~= nil then f.run(player_table) end
    end

    -- Update the validity of all elements of the factory
    Factory.update_validity(player_table.factory)
end

-- Overwrites the factorio global data with the new data in lua-global
function loader.finish()
    for _, data_type in ipairs(data_types) do
        global["all_" .. data_type] = new["all_" .. data_type]
    end
    new = nil

    run_on_load()
end


-- Runs the update proceedure for a simple 1-dimensional kind of prototype
function loader.util.simple_update(player_table, type)
    local preferences = player_table.preferences
    local plural_type = type .. "s"
    local new_id = new["all_" .. plural_type].map[preferences["preferred_" .. type].name]
    if new_id ~= nil then
        preferences["preferred_" .. type] = new["all_" .. plural_type][plural_type][new_id]
    else
        preferences["preferred_" .. type] = data_util.base_data["preferred_" .. type](new)
    end  
end


-- Update preferred belt
function loader.belts.run(player_table)
    loader.util.simple_update(player_table, "belt") 
end

-- Update preferred fuel
function loader.fuels.run(player_table)
    loader.util.simple_update(player_table, "fuel") 
end

-- Update preferred beacon
function loader.beacons.run(player_table)
    loader.util.simple_update(player_table, "beacon") 
end

-- Update default machines
function loader.machines.run(player_table)
    local preferences = player_table.preferences
    local default_machines = {categories = {}, map = {}}

    for new_category_id, new_category in ipairs(new.all_machines.categories) do
        local machine_found = false
        local old_category_id = preferences.default_machines.map[new_category.name]
        if old_category_id ~= nil then  -- Category found, default machine might not exist anymore
            local old_default_machine = preferences.default_machines.categories[old_category_id]
            local new_machine_id = new_category.map[old_default_machine.name]
            if new_machine_id ~= nil then  -- Old machine still exists, apply it
                default_machines.categories[new_category_id] = new_category.machines[new_machine_id]
                default_machines.map[new_category.name] = new_category_id
                machine_found = true
            end
        end
        if not machine_found then  -- Choose new default, if the old default is no longer valid
            default_machines.categories[new_category_id] = new_category.machines[1]
            default_machines.map[new_category.name] = new_category_id
        end
    end

    preferences.default_machines = default_machines
end
loader = {
    machines = {},
    belts = {},
    fuels = {}
}

-- The purpose of a loader is to recreate the global tables containing all relevant data types.
-- It also updates the factories to the new id's of all those datasets.
-- Its purpose is to not lose any data, so if a dataset of a factory-dataset doesn't exist anymore
-- in the newly loaded global tables, it saves the name in string-form instead and makes the
-- concerned factory-dataset invalid. This accomplishes that invalid data is only permanently
-- removed when the user tells the subfactory to repair itself, giving him a chance to re-add the
-- missing mods. It is also a better separation of responsibilities and avoids some redundant code.

-- (Load order is important here: machines->recipes->items)
local data_types = {"machines", "recipes", "items", "fuels", "belts"}

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

    -- First, update the validity of all elements of the factory
    Factory.update_validity(player_table.factory)
end

-- Overwrites the factorio global data with the new data in lua-global
function loader.finish()
    for _, data_type in ipairs(data_types) do
        global["all_" .. data_type] = new["all_" .. data_type]
    end
    new = nil

    -- Re-runs the table creation that runs on_load to incorporate the reloaded datasets
    item_recipe_map = generator.item_recipe_map()
    item_groups = generator.item_groups()
end


-- Update preferred belt
function loader.belts.run(player_table)
    local preferences = player_table.preferences
    local new_belt_id = new.all_belts.map[preferences.preferred_belt.name]
    if new_belt_id ~= nil then
        preferences.preferred_belt = new.all_belts.belts[new_belt_id]
    else
        preferences.preferred_belt = data_util.base_data.preferred_belt(new)
    end   
end


-- Update preferred fuel
function loader.fuels.run(player_table)
    local preferences = player_table.preferences
    local new_fuel_id = new.all_fuels.map[preferences.preferred_fuel.name]
    if new_fuel_id ~= nil then
        preferences.preferred_fuel = new.all_fuels.fuels[new_fuel_id]
    else
        preferences.preferred_fuel = data_util.base_data.preferred_fuel(new)
    end

    --[[ -- Update line data
    for _, subfactory in pairs(Factory.get_in_order(player_table.factory, "Subfactory")) do
        for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
            for _, line in pairs(Floor.get_in_order(floor, "Line")) do
                if line.fuel_id ~= nil then
                    local old_fuel = global.all_fuels.fuels[line.fuel_id]
                    local new_fuel_id = fuels.new.map[old_fuel.name]
                    if new_fuel_id ~= nil then
                        line.fuel_id = new_fuel_id
                    else
                        line.fuel_id = nil
                    end
                end
            end
        end
    end ]]
end


function loader.machines.run(player_table)
    --[[ -- Update line data
    for _, subfactory in pairs(Factory.get_in_order(player_table.factory, "Subfactory")) do
        for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
            for _, line in pairs(Floor.get_in_order(floor, "Line")) do
                -- Old categories and machines always exist at this point
                local old_category_name, old_machine_name

                if type(line.category_id) == "string" then
                    -- When the category is a string, the machine must be too
                    old_category_name = line.category_id
                    old_machine_name = line.machine_id
                else
                    local old_category = global.all_machines.categories[line.category_id]
                    old_category_name = old_category.name
                    
                    if type(line.machine_id) == "string" then
                        old_machine_name = line.machine_id
                    else
                        old_machine_name = old_category.machines[line.machine_id].name
                    end
                end

                local new_category_id = machines.new.map[old_category_name]
                if new_category_id == nil then  -- both category and machine are 'invalid'
                    line.category_id = old_category_name
                    line.machine_id = old_machine_name
                else  -- the category is valid
                    line.category_id = new_category_id
                    local new_machine_id = machines.new.categories[new_category_id].map[old_machine_name]
                    if new_machine_id == nil then  -- only the machine is 'invalid'
                        line.machine_id = old_machine_name
                    else  -- both the machine and category are valid
                        line.machine_id = new_machine_id
                    end
                end
            end
        end
    end ]]

    -- Update default machines
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
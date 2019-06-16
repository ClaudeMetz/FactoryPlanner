loader = {
    machines = {},
    belts = {},
    fuels = {}
}

local data_types = {"machines", "belts", "fuels"}

-- Generates the new data and mapping_tables and saves them to lua-globals
function loader.setup()
    for _, data_type in ipairs(data_types) do
        _G[data_type] = {}
        _G[data_type].new = generator["all_" .. data_type]()
    end

    
end

-- Updates the relevant data of the given player to fit the new data
function loader.run(player_table)
    for _, data_type in ipairs(data_types) do
        loader[data_type].run(player_table)
    end
end

-- Overwrites the factorio global data with the new data in lua-global
function loader.finish()
    for _, data_type in ipairs(data_types) do
        global["all_" .. data_type] = _G[data_type].new
        _G[data_type] = nil
    end

    global.all_recipes = generator.all_recipes()
    global.all_items = generator.all_items()

    -- Re-runs the table creation that runs on_load to incorporate the migrated datasets
    item_recipe_map = generator.item_recipe_map()
end


function loader.belts.run(player_table)
    local preferences = player_table.preferences
    local old_belt = global.all_belts.belts[preferences.preferred_belt_id]
    local new_belt_id = belts.new.map[old_belt.name]
    if new_belt_id ~= nil then
        preferences.preferred_belt_id = new_belt_id
    else
        preferences.preferred_belt_id = belts.new.belts[1].id
    end   
end


function loader.machines.run(player_table)
    -- Update line data
    for _, subfactory in pairs(Factory.get_in_order(player_table.factory, "Subfactory")) do
        for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
            for _, line in pairs(Floor.get_in_order(floor, "Line")) do
                local category_found = false
                local old_category = global.all_machines.categories[line.category_id]
                if old_category ~= nil then
                    local new_category_id = machines.new.map[old_category.name]
                    if new_category_id ~= nil then
                        local old_machine = old_category.machines[line.machine_id]
                        if old_machine ~= nil then
                            line.category_id = new_category_id
                            -- machine_id might still be nil here
                            line.machine_id = machines.new.categories[new_category_id].map[old_machine.name]
                            category_found = true
                        end
                    end
                end
                if not category_found then  -- Reset category and machine if no match is found
                    line.category_id = nil
                    line.machine_id = nil
                end
            end
        end
    end

    -- Update default machines
    local preferences = player_table.preferences
    local default_machines = {machines = {}, map = {}}

    for new_category_id, new_category in ipairs(machines.new.categories) do
        local machine_found = false
        local old_category_id = preferences.default_machines.map[new_category.name]
        if old_category_id ~= nil then  -- Category found, default machine might not exist anymore
            local old_default_machine_id = preferences.default_machines.machines[old_category_id]
            local old_machine = global.all_machines.categories[old_category_id].machines[old_default_machine_id]
            local new_machine_id = new_category.map[old_machine.name]
            if new_machine_id ~= nil then  -- Old machine still exists, apply it
                default_machines.machines[new_category_id] = new_machine_id
                default_machines.map[new_category.name] = new_category_id
                machine_found = true
            end
        end
        if not machine_found then  -- Choose new default, if the old default is no longer valid
            default_machines.machines[new_category_id] = new_category.machines[1].id
            default_machines.map[new_category.name] = new_category_id
        end
    end

    preferences.default_machines = default_machines
end


function loader.fuels.run(player_table)
    local preferences = player_table.preferences

    -- Update preferred fuel
    local old_fuel = global.all_fuels.fuels[preferences.preferred_fuel_id]
    local new_fuel_id = fuels.new.map[old_fuel.name]
    if new_fuel_id ~= nil then
        preferences.preferred_fuel_id = new_fuel_id
    else
        local coal_id = fuels.new.map["coal"]
        if coal_id ~= nil then
            preferences.preferred_fuel_id = coal_id
        else
            preferences.preferred_fuel_id = fuels.new.fuels[1].id
        end
    end

    -- Update line data
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
    end
end
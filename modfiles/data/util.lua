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

-- Returns whether the given machine can produce the given recipe
function data_util.machine.is_applicable(machine_proto, recipe)
    local item_ingredients_count = 0
    for _, ingredient in pairs(recipe.proto.ingredients) do
        -- Ingredient count does not include fluid ingredients
        if ingredient.type == "item" then item_ingredients_count = item_ingredients_count + 1 end
    end
    return (item_ingredients_count <= machine_proto.ingredient_limit)
end


-- Changes the machine either to the given machine or moves it in the given direction
-- If neither machine or direction is given, it applies the default machine for the category
-- Returns false if no machine is applied because none can be found, true otherwise
function data_util.machine.change(player, line, machine, direction)
    -- Set the machine to the default one
    if machine == nil and direction == nil then
        local default_machine = data_util.machine.get_default(player, line.recipe.proto.category)
        -- If no default machine is found, this category has no machines
        if default_machine == nil then return false end
        return data_util.machine.change(player, line, default_machine, nil)

    -- Set machine directly
    elseif machine ~= nil and direction == nil then
        local machine = (machine.proto ~= nil) and machine or Machine.init_by_proto(machine)
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Returns false if no machine fits at all, so an appropriate error can be displayed
        if not data_util.machine.is_applicable(machine.proto, line.recipe) then
            return data_util.machine.change(player, line, machine, "positive")

        else
            -- Carry over the machine limit
            if machine and line.machine then
                machine.limit = line.machine.limit
                machine.hard_limit = line.machine.hard_limit
            end
            line.machine = machine

            -- Adjust parent line
            if line.parent then  -- if no parent exists, nothing is overwritten anyway
                if line.subfloor then
                    Floor.get(line.subfloor, "Line", 1).machine = machine
                elseif line.id == 1 and line.parent.origin_line then
                    line.parent.origin_line.machine = machine
                end
            end

            -- Adjust modules (ie. trim them if needed)
            Line.trim_modules(line)
            Line.summarize_effects(line)

            -- Adjust beacon (ie. remove if machine does not allow beacons)
            if line.machine.proto.allowed_effects == nil or line.recipe.proto.name == "fp-space-science-pack" then
                Line.remove_beacon(line)
            end

            return true
        end

    -- Bump machine in the given direction (takes given machine, if available)
    elseif direction ~= nil then
        local category, proto
        if machine ~= nil then
            if machine.proto then
                category = machine.category
                proto = machine.proto
            else
                category = global.all_machines.categories[global.all_machines.map[machine.category]]
                proto = machine
            end
        else
            category = line.machine.category
            proto = line.machine.proto
        end
        
        if direction == "positive" then
            if proto.id < #category.machines then
                local new_machine = category.machines[proto.id + 1]
                return data_util.machine.change(player, line, new_machine, nil)
            else
                return false
            end
        else  -- direction == "negative"
            if proto.id > 1 then
                local new_machine = category.machines[proto.id - 1]
                return data_util.machine.change(player, line, new_machine, nil)
            else
                return false            
            end
        end
    end
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
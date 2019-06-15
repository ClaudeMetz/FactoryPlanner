loader = {
    machines = {}
}

-- Generates the new data and mapping_tables and saves them to lua-globals
function loader.setup()
    loader.machines.setup()

    global.all_items = generator.all_items()
    global.all_belts = generator.all_belts()
    global.all_recipes = generator.all_recipes()
end

-- Updates the relevant data of the given player to fit the new data
function loader.run(player_table)
    loader.machines.run(player_table)
end

-- Overwrites the factorio global data with the new data in lua-global
function loader.finish()
    loader.machines.finish()
end


function loader.machines.setup()
    machines = {}
    machines.new = generator.all_machines()
end

function loader.machines.run(player_table)
    -- Update line data
    --[[ for _, subfactory in pairs(Factory.get_in_order(player_table.factory, "Subfactory")) do
        for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
            for _, line in pairs(Floor.get_in_order(floor, "Line")) do
                local old_category = global.all_machines.categories[line.category_id]
                local new_category_id = machines.new.map[old_category.name]
                if new_category_id == nil then
                    line.category_id = nil
                    line.machine_id = nil
                else
                    local old_machine = old_category.machines[line.machine_id]
                    line.category_id = new_category_id
                    -- machine_id might still be nil here
                    line.machine_id = machines.new.categories[new_category_id].map[old_machine.name]
                end
            end
        end
    end ]]

    -- Update default machines
    --[[ local preferences = player_table.preferences
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

    preferences.default_machines = default_machines ]]
end

function loader.machines.finish()
    global.all_machines = machines.new
    machines = nil
end
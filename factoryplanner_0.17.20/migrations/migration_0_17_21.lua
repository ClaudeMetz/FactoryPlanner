migration_0_17_21 = {}

function migration_0_17_21.global()
end

function migration_0_17_21.player_table(player, player_table)
    player_table.preferences.preferred_belt_id = nil
    player_table.preferences.preferred_fuel_id = nil
    player_table.preferences.preferred_default_machines = nil
end

function migration_0_17_21.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.recipe = line.recipe_name
            line.recipe_name = nil
            
            local category_name = global.all_machines.categories[line.category_id].name
            local new_category_id = new.all_machines.map[category_name]
            if new_category_id ~= nil then
                line.machine = new.all_machines.categories[new_category_id].machines[1]
            else
                Floor.remove(floor, line)
            end
            line.machine_id = nil
            
            line.fuel_id = nil

            line.recipe_energy = nil
            line.category_id = nil
            line.machine_count = nil
        end
    end
end
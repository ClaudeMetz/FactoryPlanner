migration_0_17_21 = {}

function migration_0_17_21.global()
end

function migration_0_17_21.player_table(player, player_table)
    player_table.preferences.preferred_belt_id = nil
    player_table.preferences.preferred_fuel_id = nil
    player_table.preferences.default_machines = nil
end

function migration_0_17_21.subfactory(player, subfactory)
    local classes = {"Ingredient", "Product", "Byproduct"}
    for _, class in pairs(classes) do
        for _, item in ipairs(Subfactory.get_in_order(subfactory, class)) do
            item.proto = item.name
            item.name = nil
        end
    end

    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            for _, class in pairs(classes) do
                for _, item in ipairs(Line.get_in_order(line, class)) do
                    item.proto = item.name
                    item.name = nil
                end
            end

            line.recipe = {proto = line.recipe_name}
            line.recipe_name = nil

            local category = global.all_machines.categories[line.category_id]
            local machine = category.machines[line.machine_id]
            line.machine = {
                proto = machine.name,
                category = category.name
            }
            line.machine_id = nil

            line.fuel_id = nil
            line.recipe_energy = nil
            line.category_id = nil
            line.machine_count = nil
        end
    end
end
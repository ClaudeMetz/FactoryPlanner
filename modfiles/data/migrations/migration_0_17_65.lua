migration_0_17_65 = {}

function migration_0_17_65.global()
end

function migration_0_17_65.player_table(player, player_table)
    player_table.preferences.enable_recipe_comments = nil
end

function migration_0_17_65.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.machine.limit = line.machine.count_cap
            line.machine.count_cap = nil
            line.machine.hard_limit = false
        end
    end
end
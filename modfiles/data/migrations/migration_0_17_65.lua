local migration = {}

function migration.player_table(player_table)
    player_table.preferences.enable_recipe_comments = nil
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.machine.limit = line.machine.count_cap
            line.machine.count_cap = nil
            line.machine.hard_limit = false
        end
    end
end

return migration
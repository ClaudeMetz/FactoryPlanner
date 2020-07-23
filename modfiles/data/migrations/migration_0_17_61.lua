local migration = {}

function migration.player_table(player_table)
    player_table.preferences.enable_recipe_comments = nil
end

function migration.subfactory(subfactory)
    subfactory.pollution = 0

    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.pollution = 0
        end
    end
end

return migration
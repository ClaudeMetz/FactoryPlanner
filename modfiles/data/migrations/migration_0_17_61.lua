migration_0_17_61 = {}

function migration_0_17_61.global()
end

function migration_0_17_61.player_table(player, player_table)
    player_table.preferences.enable_recipe_comments = nil
end

function migration_0_17_61.subfactory(player, subfactory)
    subfactory.pollution = 0

    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.pollution = 0
        end
    end
end
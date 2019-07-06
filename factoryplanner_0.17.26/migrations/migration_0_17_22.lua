migration_0_17_22 = {}

function migration_0_17_22.global()
end

function migration_0_17_22.player_table(player, player_table)
end

function migration_0_17_22.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.Modules = Collection.init()
            line.recipe.energy = nil
            Line.summarize_effects(line)
        end
    end
end
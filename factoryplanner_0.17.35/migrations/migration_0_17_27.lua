migration_0_17_27 = {}

function migration_0_17_27.global()
end

function migration_0_17_27.player_table(player, player_table)
end

function migration_0_17_27.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_in_order(subfactory, "Floor")) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.Module = Collection.init()
            line.recipe.energy = nil
            Line.total_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
        end
    end
end
migration_0_17_55 = {}

function migration_0_17_55.global()
end

function migration_0_17_55.player_table(player, player_table)
end

function migration_0_17_55.subfactory(player, subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.fuel = nil
            line.Fuel = Collection.init()

            if line.recipe ~= nil then line.recipe.production_type = "produce" end
        end
    end
end
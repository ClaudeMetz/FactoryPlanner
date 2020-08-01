local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    subfactory.scopes = {}

    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.Product = Collection.init()
            line.Byproduct = Collection.init()
            line.Ingredient = Collection.init()
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
end

return migration
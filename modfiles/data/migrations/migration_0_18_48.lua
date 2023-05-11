local migration = {}

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

return migration

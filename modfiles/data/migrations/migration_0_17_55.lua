local migration = {}

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.fuel = nil
            line.Fuel = Collection.init()

            if line.recipe ~= nil then line.recipe.production_type = "produce" end
        end
    end
end

return migration
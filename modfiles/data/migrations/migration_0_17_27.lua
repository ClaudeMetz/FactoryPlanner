local migration = {}

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.Module = Collection.init()
            line.recipe.energy = nil
            Line.total_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
        end
    end
end

return migration
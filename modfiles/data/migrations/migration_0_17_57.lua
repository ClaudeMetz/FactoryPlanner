local migration = {}

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.uncapped_production_ratio = 0
        end
    end
end

return migration
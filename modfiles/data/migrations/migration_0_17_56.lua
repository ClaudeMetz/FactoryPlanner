local migration = {}

function migration.subfactory(subfactory)
    for _, item in pairs(Subfactory.get_in_order(subfactory, "Ingredient")) do item.top_level=true end
    for _, item in pairs(Subfactory.get_in_order(subfactory, "Byproduct")) do item.top_level=true end

    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            for _, item in pairs(Line.get_in_order(line, "Ingredient")) do item.satisfied_amount = 0 end
        end
    end
end

return migration
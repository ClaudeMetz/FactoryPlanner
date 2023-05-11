local migration = {}

function migration.subfactory(subfactory)
    -- Revert all the crap I did with the previous version
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            if line.subfloor then line.machine = nil end
        end
    end
end

return migration

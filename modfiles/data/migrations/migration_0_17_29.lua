local migration = {}

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            local beacon = line.beacon
            if beacon ~= nil then beacon.module.parent = beacon end
        end
    end
end

return migration
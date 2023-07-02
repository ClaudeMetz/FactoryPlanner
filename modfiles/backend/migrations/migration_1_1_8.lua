---@diagnostic disable

local migration = {}

function migration.subfactory(subfactory)
    -- Revert all the crap I did with the previous version
    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            if line.subfloor then line.machine = nil end
        end
    end
end

return migration

---@diagnostic disable

local migration = {}

function migration.subfactory(subfactory)
    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            if line.machine and line.machine.fuel and line.machine.fuel.proto == nil then
                floor.Line.datasets[line.id] = nil
                floor.Line.count = floor.Line.count - 1
            end
        end
    end
end

return migration

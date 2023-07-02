---@diagnostic disable

local migration = {}

function migration.subfactory(subfactory)
    subfactory.scopes = {}

    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            local function init() return {datasets={}, index=0, count=0, class="Collection"} end
            line.Product = init()
            line.Byproduct = init()
            line.Ingredient = init()
        end
    end
end

return migration

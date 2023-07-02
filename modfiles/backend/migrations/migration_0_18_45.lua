---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    player_table.ui_state.current_activity = nil
end

function migration.subfactory(subfactory)
    for _, floor in pairs(subfactory.Floor.datasets) do
        for _, line in pairs(floor.Line.datasets) do
            if line.machine and line.machine.fuel then line.machine.fuel.satisfied_amount = 0 end

            local function init() return {datasets={}, index=0, count=0, class="Collection"} end
            line.Product = init()
            line.Byproduct = init()
            line.Ingredient = init()
        end
    end
end

return migration

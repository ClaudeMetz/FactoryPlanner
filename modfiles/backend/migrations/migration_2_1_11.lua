---@diagnostic disable

local migration = {}

local function solver_name(matrix_solver_active)
    return (matrix_solver_active) and "gaussian" or "sequential"
end

function migration.player_table(player_table)
    player_table.context.history = {
        stack = {},
        position = 0
    }

    player_table.preferences.default_solver = solver_name(player_table.preferences.prefer_matrix_solver)

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            factory.solver = solver_name(factory.matrix_solver_active)
            factory.matrix_solver_active = nil
        end
    end
end

function migration.packed_factory(packed_factory)
    packed_factory.solver = solver_name(packed_factory.matrix_solver_active)
    packed_factory.matrix_solver_active = nil
end

return migration

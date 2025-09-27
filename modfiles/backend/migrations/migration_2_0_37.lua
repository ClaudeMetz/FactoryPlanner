---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            factory.matrix_solver_active = (factory.matrix_free_items ~= nil)
            factory.matrix_free_items = factory.matrix_free_items or {}
        end
    end
end

function migration.packed_factory(packed_factory)
    packed_factory.matrix_solver_active = (packed_factory.matrix_free_items ~= nil)
    packed_factory.matrix_free_items = packed_factory.matrix_free_items or {}
end

return migration

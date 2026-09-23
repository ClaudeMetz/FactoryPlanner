---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local function migrate_floor(floor, solver_name, free_items)
        floor.solver = solver_name
        floor.gaussian_free_items = free_items and lib.flib.shallow_copy(free_items) or {}

        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                migrate_floor(line_object, solver_name)
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            migrate_floor(factory.top_floor, factory.solver, factory.matrix_free_items)
            factory.solver = nil
        end
    end
end

function migration.packed_factory(packed_factory)
    local function migrate_floor(floor, solver_name, free_items)
        floor.solver = solver_name
        floor.gaussian_free_items = free_items and lib.flib.shallow_copy(free_items) or {}

        for _, line_object in ipairs(floor.lines) do
            if line_object.class == "Floor" then
                migrate_floor(line_object, solver_name)
            end
        end
    end

    migrate_floor(packed_factory.top_floor, packed_factory.solver, packed_factory.matrix_free_items)
    packed_factory.solver = nil
end

return migration

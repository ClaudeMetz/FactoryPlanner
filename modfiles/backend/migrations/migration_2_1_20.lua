---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    local function migrate_floor(floor)
        for line_object in floor:iterator() do
            if line_object.class == "Floor" then
                migrate_floor(line_object)
            else
                if floor.level > 2 or floor.level == 2 and line_object ~= floor.first then
                    line_object.machine.limit = nil
                    line_object.machine.force_limit = nil
                end
            end
        end
    end

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            migrate_floor(factory.top_floor)
        end
    end
end

function migration.packed_factory(packed_factory)
    local function migrate_floor(floor)
        for i, line_object in ipairs(floor.lines) do
            if line_object.class == "Floor" then
                migrate_floor(line_object)
            else
                if floor.level > 2 or floor.level == 2 and i > 1 then
                    line_object.machine.limit = nil
                    line_object.machine.force_limit = nil
                end
            end
        end
    end

    migrate_floor(packed_factory.top_floor)
end

return migration

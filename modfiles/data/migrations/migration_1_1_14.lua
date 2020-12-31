local migration = {}

function migration.global()
end

function migration.player_table(player_table)
end

function migration.subfactory(subfactory)
    for _, floor in pairs(Subfactory.get_all_floors(subfactory)) do
        for _, line in pairs(Floor.get_in_order(floor, "Line")) do
            line.done = false
        end
    end
end

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            packed_line.done = false

            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration
---@diagnostic disable

local migration = {}

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            else
                packed_line.Product = {objects={}, class="Collection"}
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration

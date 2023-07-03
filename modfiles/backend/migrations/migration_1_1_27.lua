---@diagnostic disable

local migration = {}

function migration.packed_subfactory(packed_subfactory)
    local function update_lines(floor)
        for _, packed_line in ipairs(floor.Line.objects) do
            if packed_line.subfloor then
                update_lines(packed_line.subfloor)
            elseif packed_line.beacon and packed_line.beacon.module then
                local beacon = packed_line.beacon
                beacon.Module = {objects={beacon.module}, class="Collection"}
                beacon.module_count = module.amount
            end
        end
    end
    update_lines(packed_subfactory.top_floor)
end

return migration

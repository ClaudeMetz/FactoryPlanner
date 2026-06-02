---@diagnostic disable

local migration = {}

function migration.packed_factory(packed_factory)
    packed_factory.mining_productivity = nil

    local function iterate_floor(packed_floor)
        for _, packed_line in pairs(packed_floor.lines) do
            if packed_line.class == "Floor" then
                iterate_floor(packed_line)
            elseif packed_line.beacon then
                packed_line.beacon.amount = math.ceil(packed_line.beacon.amount)
            end
        end
    end
    iterate_floor(packed_factory.top_floor)
end

return migration

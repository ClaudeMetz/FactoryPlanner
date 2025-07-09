---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for factory in player_table.district:iterator() do
        if factory.item_request_proxy and factory.item_request_proxy.valid then
            factory.item_request_proxy.destroy{raise_destroy=false}
        end
        factory.item_request_proxy = nil

        factory.mining_productivity = nil

        local function iterate_floor(floor)
            for line in floor:iterator() do
                if line.class == "Floor" then
                    iterate_floor(line)
                elseif line.beacon then
                    line.beacon.amount = math.ceil(line.beacon.amount)
                end
            end
        end
        iterate_floor(factory.top_floor)
    end
end

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

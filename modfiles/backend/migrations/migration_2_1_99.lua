---@diagnostic disable

local SimpleItem = require("backend.data.SimpleItem")

local migration = {}

function migration.player_table(player_table)
    local function migrate_floor(floor)
        for i, item_proto in ipairs(floor.gaussian_free_items) do
            --- Avoid constructor to mitigate breaking migrations
            local simple_item = {
                class = "SimpleItem",
                proto = item_proto,
                amount = 0
            }
            setmetatable(simple_item, SimpleItem)
            floor.gaussian_free_items[i] = simple_item
        end

        for line_object in floor:iterator() do
            if line_object.class == "Floor" then migrate_floor(line_object) end
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
        for i, packed_item_proto in ipairs(floor.gaussian_free_items or {}) do
            local packed_simple_item = {
                class = "SimpleItem",
                proto = packed_item_proto,
                amount = 0
            }
            floor.gaussian_free_items[i] = packed_simple_item
        end

        for _, line_object in ipairs(floor.lines) do
            if line_object.class == "Floor" then migrate_floor(line_object) end
        end
    end

    migrate_floor(packed_factory.top_floor)
end

return migration

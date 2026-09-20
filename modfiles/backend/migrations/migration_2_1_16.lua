---@diagnostic disable

local FactoryItem = require("backend.data.FactoryItem")
local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                if product.class == "TLProduct" then
                    local item = FactoryItem.init(product.proto)
                    item.defined_by = product.defined_by
                    item.required_amount = product.required_amount
                    item.belt_proto = product.belt_proto
                    item.belt_stack = product.belt_stack
                    item.amount = product.amount
                    factory:replace(product, item)
                end
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        if product.class == "TLProduct" then
            product.class = "FactoryItem"
        end
    end
end

return migration

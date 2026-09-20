---@diagnostic disable

local FactoryItem = require("backend.data.FactoryItem")
local migration = {}

local function migrate_definition(item)
    if item.required_amount == nil then return end

    if item.defined_by == "belts" then
        item.definition = {type="belts", belt_count=item.required_amount,
            belt_proto=item.belt_proto, belt_stack=item.belt_stack}
    else
        item.definition = {type="amount", amount=item.required_amount}
    end
    item.defined_by, item.required_amount = nil, nil
    item.belt_proto, item.belt_stack = nil, nil
end

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                local item = product
                if product.class == "TLProduct" then
                    item = FactoryItem.init(product.proto)
                    item.defined_by = product.defined_by
                    item.required_amount = product.required_amount
                    item.belt_proto = product.belt_proto
                    item.belt_stack = product.belt_stack
                    item.amount = product.amount
                    factory:replace(product, item)
                end
                migrate_definition(item)
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        if product.class == "TLProduct" then
            product.class = "FactoryItem"
        end
        migrate_definition(product)
    end
end

return migration

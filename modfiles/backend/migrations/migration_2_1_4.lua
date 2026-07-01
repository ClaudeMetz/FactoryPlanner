---@diagnostic disable

local TLProduct = require("backend.data.TLProduct")

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                -- Need to rebuild so the metatables work out
                local new_product = TLProduct.init(product.proto)
                new_product.defined_by = product.defined_by
                new_product.required_amount = product.required_amount
                new_product.belt_proto = product.belt_proto
                factory:replace(product, new_product)
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        product.class = "TLProduct"
    end
end

return migration

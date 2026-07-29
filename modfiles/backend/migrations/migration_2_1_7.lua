---@diagnostic disable

local migration = {}

-- Products defined by lanes are now stored as belts, with lanes being a display unit only
local function migrate_product(product)
    if product.belt_proto then product.belt_stack = 1 end

    if product.defined_by == "lanes" then
        product.defined_by = "belts"
        product.required_amount = product.required_amount * 0.5
    end
end

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                migrate_product(product)
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        migrate_product(product)
    end
end

return migration

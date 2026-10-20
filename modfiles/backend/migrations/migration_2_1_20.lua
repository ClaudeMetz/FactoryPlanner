---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for product in factory:iterator() do
                product.active = true
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    for _, product in pairs(packed_factory.products) do
        product.active = true
    end
end

return migration

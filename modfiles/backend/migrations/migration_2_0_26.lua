---@diagnostic disable

local migration = {}

local function migrate_product(product)
    local proto = product.proto
    if (proto.type or proto.category) ~= "fluid" then return end

    local map = TEMPERATURE_MAP[proto.name]
    if map == nil then return end  -- fluid without any temperatures

    product.proto = {name=map[1].name, category="fluid", data_type="items", simplified=true}
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

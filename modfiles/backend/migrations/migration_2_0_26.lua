---@diagnostic disable

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            for _, product in pairs(factory:as_list()) do
                if product.proto.type == "fluid" then
                    local map = TEMPERATURE_MAP[product.proto.name]
                    if #map == 1 then
                        product.proto = prototyper.util.find("items", map[1].name, "fluid")
                    else
                        factory:remove(product)
                    end
                end
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    local products = {}
    for _, product in pairs(packed_factory.products) do
        local map = TEMPERATURE_MAP[product.proto.name]
        if not map then   -- means it's not a fluid
            table.insert(products, product)
        elseif #map == 1 then
            product.proto = prototyper.util.find("items", map[1].name, "fluid")
            table.insert(products, product)
        end
    end
    packed_factory.products = products
end

return migration

-- Contains some structures and their 'methods' that are helpful during the calculation process
structures = {
    aggregate = {}
}

function structures.aggregate.init(player_index, floor_id)
    return {
        player_index = player_index,
        floor_id = floor_id,
        energy_consumption = 0,
        production_ratio = nil,
        Product = structures.aggregate.init_class(),
        Byproduct = structures.aggregate.init_class(),
        Ingredient = structures.aggregate.init_class(),
        Fuel = structures.aggregate.init_class(),
    }
end

function structures.aggregate.init_class()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

-- Item might be an Item-object or a simple item {type, name, amount}
function structures.aggregate.add(aggregate, class, item)
    local type = (item.proto ~= nil) and item.proto.type or item.type
    local name = (item.proto ~= nil) and item.proto.name or item.name
    local amount = item.required_amount or item.amount

    local type_table = aggregate[class][type]
    if type_table[name] == nil then
        type_table[name] = amount
    else
        type_table[name] = type_table[name] + amount
    end

    if type_table[name] == 0 then type_table[name] = nil end
end

-- Adds all the elements of the secondary class to the main one (modifies the aggregate!)
function structures.aggregate.combine_classes(aggregate, main_class, secondary_class)
    for type, items_of_type in pairs(aggregate[secondary_class]) do
        for name, amount in pairs(items_of_type) do
            local item = {type=type, name=name, amount=amount}
            structures.aggregate.add(aggregate, main_class, item)
            items_of_type[name] = nil
        end
    end
end
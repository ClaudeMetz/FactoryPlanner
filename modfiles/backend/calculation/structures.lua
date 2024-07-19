-- Contains some structures and their 'methods' that are helpful during the calculation process
local structures = {
    aggregate = {},
    class = {}
}

function structures.aggregate.init(player_index, floor_id)
    return {
        player_index = player_index,
        floor_id = floor_id,
        machine_count = 0,
        energy_consumption = 0,
        emissions = {},
        production_ratio = nil,
        uncapped_production_ratio = nil,
        Product = structures.class.init(),
        Byproduct = structures.class.init(),
        Ingredient = structures.class.init()
    }
end

-- Item might be an Item-object or a simple item {type, name, amount}
function structures.aggregate.add(aggregate, class_name, item, amount)
    structures.class.add(aggregate[class_name], item, amount)
end

function structures.aggregate.subtract(aggregate, class_name, item, amount)
    structures.class.add(aggregate[class_name], item, -(amount or item.amount))
end

function structures.aggregate.add_emissions(aggregate, emissions)
    for type, amount in pairs(emissions) do
        aggregate.emissions[type] = (aggregate.emissions[type] or 0) + amount
    end
end

-- Adds the first given aggregate to the second
function structures.aggregate.add_aggregate(from_aggregate, to_aggregate)
    to_aggregate.energy_consumption = to_aggregate.energy_consumption + from_aggregate.energy_consumption
    structures.aggregate.add_emissions(to_aggregate, from_aggregate.emissions)

    for _, class in ipairs{"Product", "Byproduct", "Ingredient"} do
        for _, item in ipairs(structures.class.to_array(from_aggregate[class])) do
            structures.aggregate.add(to_aggregate, class, item)
        end
    end
end

function structures.class.init()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

-- Item might be an Item-object or a simple item {type, name, amount}
function structures.class.add(class, item, amount)
    local type = (item.proto ~= nil) and item.proto.type or item.type
    local name = (item.proto ~= nil) and item.proto.name or item.name
    local amount_to_add = amount or item.amount

    local type_table = class[type]
    type_table[name] = (type_table[name] or 0) + amount_to_add
    if type_table[name] == 0 then type_table[name] = nil end
end

function structures.class.subtract(class, item, amount)
    structures.class.add(class, item, -(amount or item.amount))
end

-- Puts the items into their destination-class in the given aggregate, stopping for balancing
-- at the depot-class (Naming is hard, and that explanation is crap)
function structures.class.balance_items(class, aggregate, depot, destination)
    for _, item in ipairs(structures.class.to_array(class)) do
        local depot_amount = aggregate[depot][item.type][item.name]

        if depot_amount ~= nil then  -- Use up depot items, if available
            if depot_amount >= item.amount then
                structures.aggregate.subtract(aggregate, depot, item)
            else
                structures.aggregate.subtract(aggregate, depot, item, depot_amount)
                structures.aggregate.add(aggregate, destination, item, (item.amount - depot_amount))
            end

        else  -- add to destination if this item is not present in the depot
            structures.aggregate.add(aggregate, destination, item)
        end
    end
end

-- Returns an array that contains every item in the given data structure
function structures.class.to_array(class)
    local array = {}
    for type, items_of_type in pairs(class) do
        for name, amount in pairs(items_of_type) do
            table.insert(array, {
                name = name,
                type = type,
                amount = amount
            })
        end
    end
    return array
end

-- 'Deepcopies' the given class, with better performance than the generic deep copy
function structures.class.copy(class)
    local copy = structures.class.init()
    for type_name, type in pairs(class) do
        local copy_type = copy[type_name]
        for name, amount in pairs(type) do
            copy_type[name] = amount
        end
    end
    return copy
end

-- Counts the elements contained in the given class
function structures.class.count(class)
    local n = 0
    for _, items_of_type in pairs(class) do
        n = n + table_size(items_of_type)
    end
    return n
end

return structures

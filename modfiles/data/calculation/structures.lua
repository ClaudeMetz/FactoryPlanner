-- Contains some structures and their 'methods' that are helpful during the calculation process
structures = {
    aggregate = {},
    class = {}
}

function structures.aggregate.init(player_index, floor_id)
    return {
        player_index = player_index,
        floor_id = floor_id,
        machine_count = nil,
        energy_consumption = 0,
        pollution = 0,
        production_ratio = nil,
        uncapped_production_ratio = nil,
        Product = structures.class.init(),
        Byproduct = structures.class.init(),
        Ingredient = structures.class.init(),
        Fuel = structures.class.init()
    }
end

-- Item might be an Item-object or a simple item {type, name, amount}
function structures.aggregate.add(aggregate, class_name, item, amount)
    structures.class.add(aggregate[class_name], item, amount)
end

function structures.aggregate.subtract(aggregate, class_name, item, amount)
    local negative_amount = (amount ~= nil) and -amount or -item.amount
    structures.class.add(aggregate[class_name], item, negative_amount)
end

-- Adds all the elements of the secondary class to the main one (modifies the aggregate!)
function structures.aggregate.combine_classes(aggregate, main_class_name, secondary_class_name)
    for type, items_of_type in pairs(aggregate[secondary_class_name]) do
        for name, amount in pairs(items_of_type) do
            local item = {type=type, name=name, amount=amount}
            structures.aggregate.add(aggregate, main_class_name, item)
            items_of_type[name] = nil
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
    local amount = amount or (item.required_amount or item.amount)
    
    local type_table = class[type]
    if type_table[name] == nil then
        type_table[name] = amount
    else
        type_table[name] = type_table[name] + amount
    end
    
    if type_table[name] == 0 then type_table[name] = nil end
end

function structures.class.subtract(class, item, amount)
    local negative_amount = (amount ~= nil) and -amount or -item.amount
    structures.class.add(class, item, negative_amount)
end

-- Returns an array that contains every item in the given data structure
function structures.class.to_array(class)
    local array = {}
    for type, items_of_type in pairs(class) do
        for name, amount in pairs(items_of_type) do
            local item = {
                name = name,
                type = type,
                amount = amount
            }
            table.insert(array, item)
        end
    end
    return array
end
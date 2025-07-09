local structures = {
    aggregate = {},
    class = {}
}

---@class SolverAgggregate
---@field player_index integer
---@field floor_id integer
---@field machine_count number
---@field energy_consumption number
---@field emissions number
---@field production_ratio number?
---@field Product SolverClass
---@field Byproduct SolverClass
---@field Ingredient SolverClass

---@param player_index integer
---@param floor_id integer
---@return SolverAgggregate
function structures.aggregate.init(player_index, floor_id)
    return {
        player_index = player_index,
        floor_id = floor_id,
        machine_count = 0,
        energy_consumption = 0,
        emissions = 0,
        production_ratio = nil,
        Product = structures.class.init(),
        Byproduct = structures.class.init(),
        Ingredient = structures.class.init()
    }
end


---@alias SolverClass { item: SolverMap, fluid: SolverMap, entity: SolverMap }
---@alias SolverMap { [string]: number }

---@return SolverClass
function structures.class.init()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

---@alias SolverInputItem SolverItem | FPItemPrototype | SimpleItem | Ingredient | FormattedProduct

---@param class SolverClass
---@param item SolverInputItem
---@param amount number?
function structures.class.add(class, item, amount)
    local type = (item.proto ~= nil) and item.proto.type or item.type
    local name = (item.proto ~= nil) and item.proto.name or item.name
    local amount_to_add = amount or item.amount

    local type_table = class[type]
    type_table[name] = (type_table[name] or 0) + amount_to_add
    if type_table[name] == 0 then type_table[name] = nil end
end

---@param class SolverClass
---@param item SolverInputItem
---@param amount number?
function structures.class.subtract(class, item, amount)
    structures.class.add(class, item, -(amount or item.amount))
end


--- Puts the items into their destination class in the given aggregate,
---   stopping for balancing at the depot-class
---@param class SolverClass
---@param depot SolverClass
---@param destination SolverClass
function structures.class.balance_items(class, depot, destination)
    for _, item in pairs(structures.class.list(class)) do
        local depot_amount = depot[item.type][item.name]

        if depot_amount ~= nil then  -- Use up depot items, if available
            if depot_amount >= item.amount then
                structures.class.subtract(depot, item)
            else
                structures.class.subtract(depot, item, depot_amount)
                structures.class.add(destination, item, (item.amount - depot_amount))
            end

        else  -- add to destination if this item is not present in the depot
            structures.class.add(destination, item)
        end
    end
end


---@class SolverItem
---@field type string
---@field name string
---@field amount number

---@param class SolverClass
---@param copy boolean?
---@return SolverItem[]
function structures.class.list(class)
    local list = {}
    for type, items_of_type in pairs(class) do
        for name, amount in pairs(items_of_type) do
            table.insert(list, {
                name = name,
                type = type,
                amount = amount
            })
        end
    end
    return list
end

return structures

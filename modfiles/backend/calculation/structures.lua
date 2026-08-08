local _structures = {
    aggregate = {},
    class = {}
}

---@alias SolverInputItem SolverItem | FPItemPrototype | SimpleItem | Ingredient | FormattedProduct | Fuel
---@alias SolverItemKey string `<item.proto.type>/<item.proto.name>`

local SEPARATOR = "/"

---@param item SolverInputItem
---@return SolverItemKey
function _structures.pack_item(item)
    local type = item.proto and item.proto.type or item.type
    local name = item.proto and item.proto.name or item.name
    return type .. SEPARATOR .. name
end

---@param item_key SolverItemKey
---@param amount number?
---@return SolverItem
function _structures.unpack_item(item_key, amount)
    local unpacked = lib.split_string(item_key, SEPARATOR)
    local type = unpacked[1]  ---@as string
    local name = unpacked[2]  ---@as string
    return {
        type = type,
        name = name,
        amount = amount or 0
    }
end

---@class SolverAggregate
---@field floor_id integer
---@field machine_amount number
---@field production_ratio number?
---@field Product SolverClass
---@field Byproduct SolverClass
---@field Ingredient SolverClass
---@field known_byproducts SolverSet

---@param floor_id integer
---@return SolverAggregate
function _structures.aggregate.init(floor_id)
    return {
        floor_id = floor_id,
        machine_amount = 0,
        production_ratio = nil,
        Product = _structures.class.init(),
        Byproduct = _structures.class.init(),
        Ingredient = _structures.class.init(),
        known_byproducts = {item = {}, fluid = {}, entity = {}}
    }
end

---@alias SolverClass { item: SolverMap, fluid: SolverMap, entity: SolverMap }
---@alias SolverMap table<string, number>
---@alias SolverSet table<ItemType, table<ItemName, true>>

---@return SolverClass
function _structures.class.init()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

---@param class SolverClass
---@param item SolverInputItem
---@param amount number?
function _structures.class.add(class, item, amount)
    local type = (item.proto ~= nil) and item.proto.type or item.type
    local name = (item.proto ~= nil) and item.proto.name or item.name
    local amount_to_add = amount or item.amount or 0

    local type_table = class[type]
    type_table[name] = (type_table[name] or 0) + amount_to_add
    if type_table[name] == 0 then type_table[name] = nil end
end

---@param class SolverClass
---@param item SolverInputItem
---@param amount number?
function _structures.class.subtract(class, item, amount)
    _structures.class.add(class, item, -(amount or item.amount))
end


--- Puts the items into their destination class in the given aggregate,
---   stopping for balancing at the depot-class
---@param class SolverClass
---@param depot SolverClass
---@param destination SolverClass
function _structures.class.balance_items(class, depot, destination)
    for _, item in pairs(_structures.class.list(class)) do
        local depot_amount = depot[item.type][item.name]  ---@type number

        if depot_amount ~= nil then  -- Use up depot items, if available
            if depot_amount >= item.amount then
                _structures.class.subtract(depot, item)
            else
                _structures.class.subtract(depot, item, depot_amount)
                _structures.class.add(destination, item, (item.amount - depot_amount))
            end

        else  -- add to destination if this item is not present in the depot
            _structures.class.add(destination, item)
        end
    end
end


---@class SolverItem
---@field type string
---@field name string
---@field amount number
---@field temperature float?

---@param class SolverClass
---@return SolverItem[]
function _structures.class.list(class)
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

return _structures

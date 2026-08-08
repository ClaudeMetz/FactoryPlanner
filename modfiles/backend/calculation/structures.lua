local _structures = {
    aggregate = {},
    map = {}
}

---@class SolverItem
---@field type string
---@field name string
---@field amount number
---@field temperature float?

---@alias SolverInputItem SolverItem | FPItemPrototype | SimpleItem | Ingredient | FormattedProduct | TLProduct | Fuel
---@alias SolverItemKey string `<item.proto.type>/<item.proto.name>`
---@alias SolverMap table<SolverItemKey, number>
---@alias SolverSet table<SolverItemKey, true>

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
    local _, temperature = lib.temperature.name_split(name)
    return {
        type = type,
        name = name,
        temperature = temperature,
        amount = amount or 0
    }  ---@type SolverItem
end

---@class SolverAggregate
---@field floor_id integer
---@field machine_amount number
---@field production_ratio number?
---@field products SolverMap
---@field byproducts SolverMap
---@field ingredients SolverMap
---@field known_byproducts SolverSet

---@param floor_id integer
---@return SolverAggregate
function _structures.aggregate.init(floor_id)
    return {
        floor_id = floor_id,
        machine_amount = 0,
        production_ratio = nil,
        products = {},
        byproducts = {},
        ingredients = {},
        known_byproducts = {}
    }  ---@type SolverAggregate
end

---@param map SolverMap
---@param item SolverInputItem
---@param amount number?
function _structures.map.add(map, item, amount)
    local key = _structures.pack_item(item)
    local amount_to_add = amount or item.amount or 0

    map[key] = (map[key] or 0) + amount_to_add
    if map[key] < MAGIC_NUMBERS.margin_of_error and map[key] > -MAGIC_NUMBERS.margin_of_error then
        map[key] = nil
    end
end

---@param map SolverMap
---@param item SolverInputItem
---@param amount number?
function _structures.map.subtract(map, item, amount)
    _structures.map.add(map, item, -(amount or item.amount))
end

--- Puts the items into their destination class in the given aggregate,
---   stopping for balancing at the depot-class
---@param map SolverMap
---@param depot SolverMap
---@param destination SolverMap
function _structures.map.balance_items(map, depot, destination)
    for _, item in pairs(_structures.map.list(map)) do
        local depot_amount = depot[_structures.pack_item(item)]  ---@type number

        if depot_amount ~= nil then  -- Use up depot items, if available
            if depot_amount >= item.amount then
                _structures.map.subtract(depot, item)
            else
                _structures.map.subtract(depot, item, depot_amount)
                _structures.map.add(destination, item, (item.amount - depot_amount))
            end

        else  -- add to destination if this item is not present in the depot
            _structures.map.add(destination, item)
        end
    end
end

---@param map SolverMap
---@return SolverItem[]
function _structures.map.list(map)
    local list = {}
    for item_key, amount in pairs(map) do
        table.insert(list, _structures.unpack_item(item_key, amount))
    end
    return list
end

return _structures

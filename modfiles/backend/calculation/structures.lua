local _structures = {
    aggregate = {},
    map = {}
}

---@class SolverItem
---@field type string
---@field name string
---@field amount number
---@field temperature float?

---@alias SolverInputItem SolverItem | FPItemPrototype | SimpleItem | Ingredient | FormattedProduct | FactoryItem | Fuel
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
    local separator_index = string.find(item_key, SEPARATOR, 1, true)  ---@as integer
    local type = string.sub(item_key, 1, separator_index - 1)
    local name = string.sub(item_key, separator_index + 1)
    local _, temperature = lib.temperature.name_split(name)
    return {
        type = type,
        name = name,
        temperature = temperature,
        amount = amount or 0
    }  ---@type SolverItem
end

---@class SolverAggregate
---@field floor_id ObjectID
---@field machine_amount number
---@field crafts_per_second number?
---@field products SolverMap
---@field byproducts SolverMap
---@field ingredients SolverMap
---@field known_byproducts SolverSet

---@param floor_id ObjectID
---@return SolverAggregate
function _structures.aggregate.init(floor_id)
    return {
        floor_id = floor_id,
        machine_amount = 0,
        crafts_per_second = nil,
        products = {},
        byproducts = {},
        ingredients = {},
        known_byproducts = {}
    }  ---@type SolverAggregate
end

---@param map SolverMap
---@param item SolverInputItem
---@param amount number?
---@param round_errors boolean?
function _structures.map.add(map, item, amount, round_errors)
    local key = _structures.pack_item(item)
    local amount_to_add = amount or item.amount or 0

    map[key] = (map[key] or 0) + amount_to_add
    if round_errors then
        local threshold = math.abs(amount_to_add * MAGIC_NUMBERS.margin_of_error)
        if map[key] < threshold and map[key] > -threshold then map[key] = nil end
    else
        if map[key] == 0 then map[key] = nil end
    end
end

---@param map SolverMap
---@param item SolverInputItem
---@param amount number?
---@param round_errors boolean?
function _structures.map.subtract(map, item, amount, round_errors)
    _structures.map.add(map, item, -(amount or item.amount), round_errors)
end

--- If the 2 maps contain the same item, cancel out the lowest portion of the item from both maps.
--- If a map contains negative values, remove it and add it as positive to the other map
---@param map1 SolverMap
---@param map2 SolverMap
---@param round_errors boolean?
function _structures.map.reduce_items(map1, map2, round_errors)
    for item_key, value1 in pairs(map1) do
        local item = _structures.unpack_item(item_key)
        local value2 = map2[item_key]

        if value2 and value1 == value2 then
            map1[item_key] = nil
            map2[item_key] = nil
        elseif value2 and value1 > value2 then
            _structures.map.subtract(map1, item, value2, round_errors)
            map2[item_key] = nil
        elseif value2 and value1 < value2 or value1 < 0 then
            _structures.map.subtract(map2, item, value1, round_errors)
            map1[item_key] = nil
        end
    end

    for item_key, value2 in pairs(map2) do
        local item = _structures.unpack_item(item_key)
        if value2 < 0 then
            _structures.map.subtract(map1, item, value2, round_errors)
            map2[item_key] = nil
        end
    end
end

--- Puts the items into their destination class in the given aggregate,
---   stopping for balancing at the depot-class
---@param map SolverMap
---@param depot SolverMap
---@param destination SolverMap
---@param round_errors boolean?
function _structures.map.balance_items(map, depot, destination, round_errors)
    local map_copy = lib.flib.shallow_copy(map)
    _structures.map.reduce_items(map_copy, depot, round_errors)
    for _, item in pairs(_structures.map.list(map_copy)) do
        _structures.map.add(destination, item, item.amount, round_errors)
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

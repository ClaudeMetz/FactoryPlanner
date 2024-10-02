-- Contains some structures and their 'methods' that are helpful during the calculation process
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
---@alias SolverMap { [string]: SolverItem }

---@class SolverItem
---@field type string
---@field name string
---@field amount number

---@return SolverClass
function structures.class.init()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

---@class RecipeItem
---@field type string
---@field name string
---@field amount number
---@field temperature float?

---@param class SolverClass
---@param item RecipeItem
---@param amount number?
function structures.class.add(class, item, amount)
    local amount_to_add = amount or item.amount
    if amount_to_add == 0 then return end

    local type_table = class[item.type]
    local name = item.name

    type_table[name] = type_table[name] or {}
    for index, existing in pairs(type_table[name]) do
        -- No additional properties yet, so if an item exists, it's the one
        existing.amount = existing.amount + amount_to_add

        if existing.amount == 0 then table.remove(type_table[name], index) end
        if #type_table[name] == 0 then type_table[name] = nil end
        return
    end

    -- If it gets to here, the given skewer is not present in the class
    table.insert(type_table[name], {
        type = item.type,
        name = name,
        amount = amount_to_add
    })
end

---@param class SolverClass
---@param item RecipeItem
---@param amount number?
function structures.class.subtract(class, item, amount)
    structures.class.add(class, item, -(amount or item.amount))
end

---@param class SolverClass
---@param item RecipeItem
---@return SolverItem?
function structures.class.find(class, item)
    local map = class[item.type][item.name]
    if not map then return nil end

    for _, solver_item in pairs(map) do
        -- No filtering needed as items don't have additional properties yet
        return solver_item
    end
end

---@param class SolverClass
---@param copy boolean?
---@return RecipeItem[]
function structures.class.list(class, copy)
    local list = {}
    for _, type_list in pairs(class) do
        for _, item_list in pairs(type_list) do
            for _, item in pairs(item_list) do
                table.insert(list, item)
            end
        end
    end
    return (copy) and ftable.deep_copy(list) or list
end

-- Puts the items into their destination class in the given aggregate,
--   stopping for balancing at the depot-class
---@param class SolverClass
---@param depot SolverClass
---@param destination SolverClass
function structures.class.balance_items(class, depot, destination)
    for _, item in pairs(structures.class.list(class)) do
        local depot_item = structures.class.find(depot, item)

        if depot_item ~= nil then  -- Use up depot items, if available
            if depot_item.amount >= item.amount then
                structures.class.subtract(depot, item)
            else
                structures.class.subtract(depot, item, depot_item.amount)
                structures.class.add(destination, item, (item.amount - depot_item.amount))
            end

        else  -- add to destination if this item is not present in the depot
            structures.class.add(destination, item)
        end
    end
end


return structures

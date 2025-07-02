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
---@field desired_products SolverClass
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
        desired_products = structures.class.init(),
        Product = structures.class.init(),
        Byproduct = structures.class.init(),
        Ingredient = structures.class.init()
    }
end


---@alias SolverClass { item: SolverMap, fluid: SolverMap, entity: SolverMap }
---@alias SolverMap { [string]: SolverItem }

-- NOTE: This is overly generic, can be prototype too in usage maybe?
---@class SolverItem
---@field type string
---@field name string
---@field amount number
---@field minimum_temperature float?
---@field maximum_temperature float?
---@field temperature float?

---@return SolverClass
function structures.class.init()
    return {
        item = {},
        fluid = {},
        entity = {}
    }
end

---@param class SolverClass
---@param item SolverItem
---@param amount number?
function structures.class.add(class, item, amount)
    local amount_to_add = amount or item.amount
    if amount_to_add == 0 then return end

    local type_table = class[item.type]
    local name = item.name

    type_table[name] = type_table[name] or {}
    for index, existing in pairs(type_table[name]) do
        if existing.minimum_temperature == item.minimum_temperature and
                existing.maximum_temperature == item.maximum_temperature then
            existing.amount = existing.amount + amount_to_add

            -- NOTE does this iteration work properly? as it's removing while iterating forwards
            if existing.amount == 0 then table.remove(type_table[name], index) end
            if #type_table[name] == 0 then type_table[name] = nil end
            return
        end
    end

    -- If it gets to here, the given skewer is not present in the class
    table.insert(type_table[name], {
        type = item.type,
        name = name,
        amount = amount_to_add,
        minimum_temperature = item.minimum_temperature,
        maximum_temperature = item.maximum_temperature
    })
end

---@param class SolverClass
---@param item SolverItem
---@param amount number?
function structures.class.subtract(class, item, amount)
    structures.class.add(class, item, -(amount or item.amount))
end

-- NOTE should be match_add no? to be more generic?
---@param class SolverClass
---@param item SolverItem
---@param amount number
function structures.class.match_subtract(class, item, amount)
    if not item.temperature then
        structures.class.subtract(class, item, amount)
    else
        local name = string.gsub(item.name, "%-+[0-9]+$", "")
        local map = class[item.type][name]
        for i=#map, 1, -1 do  -- reverse iteration so removal is possible
            -- NOTE might not want to reverse-iterate since it's weird for the user
            local solver_item = map[i]
            local min_temp = solver_item.minimum_temperature
            local max_temp = solver_item.maximum_temperature
            if (not min_temp or min_temp <= item.temperature) and
                    (not max_temp or max_temp >= item.temperature) then
                local amount_to_subtract = math.min(amount, solver_item.amount)
                structures.class.subtract(class, solver_item, amount_to_subtract)
                amount = amount - amount_to_subtract
            end
        end
    end
end

--- Finds the item that matches the given SKU exactly
---@param class SolverClass
---@param item SolverItem
---@return SolverItem?
function structures.class.find(class, item)
    local name = string.gsub(item.name, "%-+[0-9]+$", "")
    local map = class[item.type][name]
    if not map then return nil end

    for _, solver_item in pairs(map) do
        if solver_item.minimum_temperature == item.minimum_temperature and
                solver_item.maximum_temperature == item.maximum_temperature then
            return solver_item
        end
    end
    return nil
end

--- Finds all items that match the given SKU's temperature
---@param class SolverClass
---@param item SolverItem
---@return SolverItem[]
function structures.class.match(class, item)
    if not item.temperature then
        return { structures.class.find(class, item) }
    else
        local name = string.gsub(item.name, "%-+[0-9]+$", "")
        local map = class[item.type][name]
        if not map then return {} end

        local matches = {}
        for _, solver_item in pairs(map) do
            local min_temp = solver_item.minimum_temperature
            local max_temp = solver_item.maximum_temperature
            if (not min_temp or min_temp <= item.temperature) and
                    (not max_temp or max_temp >= item.temperature) then
                table.insert(matches, solver_item)
            end
        end
        return matches
    end
end

---@param class SolverClass
---@param copy boolean?
---@return SolverItem[]
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

--- Puts the items into their destination class in the given aggregate,
---   stopping for balancing at the depot-class
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


---@param item FormattedProduct | FPItemPrototype
---@param amount number?
---@return SolverItem solver_item
function structures.as_solver_item(item, amount)
    -- Remove temperature from name since this is treated as an ingredient in a sense
    local name = (item.temperature) and string.gsub(item.name, "%-+[0-9]+$", "") or item.name
    return {
        name = name,
        type = item.type,
        amount = amount or item.amount,
        minimum_temperature = item.temperature or nil,
        maximum_temperature = item.temperature or nil
    }
end


return structures

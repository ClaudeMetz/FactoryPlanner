local _context = {}

---@class ContextTable
---@field object_id ObjectID?
---@field cache ContextCache

---@class ContextCache
---@field district ObjectID? DistrictID
---@field factories table<ObjectID, ContextFactories> DistrictID -> ContextFactories

---@class ContextFactories
---@field factory ObjectID? FactoryID
---@field floors table<ObjectID, ObjectID> FactoryID -> FloorID

---@alias ContextObject (District | Factory | Floor)

---@param player_table PlayerTable
function _context.init(player_table)
    player_table.context = {
        object_id = nil,
        cache = {
            district = nil,
            factories = {}
        }
    }
end


--- Gets the given object type by going up the hierarchy from the current context
---@param player LuaPlayer
---@param class string
---@return ContextObject?
function _context.get(player, class)
    local object_id = lib.globals.player_table(player).context.object_id
    if object_id == nil then return nil end
    local object = OBJECT_INDEX[object_id]  ---@type ContextObject?

    while object ~= nil do
        if object.class == class then
            return object
        end
        object = object.parent  ---@as ContextObject?
    end

    return nil
end

--- Restores the appropriate floor from context cache depending on the given object
--- This covers the happy path, extra care needs to be taken when objects were removed
---@param player LuaPlayer
---@param object ContextObject
---@param force_district boolean?
function _context.set(player, object, force_district)
    local context = lib.globals.player_table(player).context
    local cache = context.cache

    if object.class == "District" then  ---@cast object District
        -- Update cache
        cache.district = object.id

        if force_district then context.object_id = object.id; return end

        -- Set lowest-down existing object
        local factory_cache = cache.factories[object.id]
        if factory_cache and factory_cache.factory then object = OBJECT_INDEX[factory_cache.factory]
        elseif object.first then object = OBJECT_INDEX[object.first.id]
        else context.object_id = object.id; return end
    end

    if object.class == "Factory" then  ---@cast object Factory
        -- Update cache
        local factory_cache = cache.factories[object.parent.id]
        if not factory_cache then
            factory_cache = {
                factory = object.id,
                floors = {}
            }
            cache.factories[object.parent.id] = factory_cache
        else
            factory_cache.factory = object.id
        end

        -- Set lowest-down existing object
        local floor_cache_id = factory_cache.floors[object.id]
        if floor_cache_id then object = OBJECT_INDEX[floor_cache_id]
        else object = OBJECT_INDEX[object.top_floor.id] end  -- always exists
    end

    if object.class == "Floor" then  ---@cast object Floor
        -- Needs to be done first so .get() can work
        context.object_id = object.id

        -- Update cache
        -- Uses .get() method to move up through eventual subfloors
        local factory = _context.get(player, "Factory")  ---@as Factory
        local floors_cache = cache.factories[factory.parent.id].floors
        -- The above cache is guaranteed to exist to be able to get here
        floors_cache[factory.id] = object.id
    end

    -- Make sure the selected factory's solve is up to date
    local factory = _context.get(player, "Factory")  ---@as Factory?
    if factory and factory.tick_of_solver_update then solver.update(player, factory) end
end

--- Cleans up after the given object was removed and tries to find a replacement
---@param player LuaPlayer
---@param object District | Factory
---@return ContextObject? replacement
function _context.remove(player, object)
    local cache = lib.globals.player_table(player).context.cache

    -- Clean up the cache from the removed object
    if object.class == "District" then
        if cache.district == object.id then cache.district = nil end
        cache.factories[object.id] = nil
    elseif object.class == "Factory" then
        local factory_cache = cache.factories[object.parent.id]
        if factory_cache.factory == object.id then factory_cache.factory = nil end
        factory_cache.floors[object.id] = nil
    end

    -- Try finding an adjacent object to return
    local filter = (object.class == "Factory") and
        { archived = object.archived } or {}  ---@type ObjectFilter

    ---@diagnostic disable-next-line: param-type-mismatch
    local previous = object.parent:find(filter, object["previous"], "previous")
    if previous then return previous end
    ---@diagnostic disable-next-line: param-type-mismatch
    local next = object.parent:find(filter, object["next"], "next")
    if next then return next end

    return nil  -- none found, caller needs to sort it out
end


---@alias FloorDestination "up" | "top"

---@param player LuaPlayer
---@param destination FloorDestination
---@return boolean success
function _context.ascend_floors(player, destination)
    local floor = _context.get(player, "Floor")  ---@as Floor?
    if floor == nil then return false end

    local selected_floor = nil
    if destination == "up" and floor.level > 1 then
        selected_floor = floor.parent
    elseif destination == "top" then
        local top_floor = _context.get(player, "Factory")--[[@cast -nil]].top_floor
        if top_floor ~= floor then selected_floor = top_floor end
    end

    if selected_floor ~= nil then
        -- Reset the subfloor we moved from if it doesn't have any additional recipes
        if floor:count() == 1 then floor.parent:replace(floor, floor.first--[[@cast -nil]]) end

        _context.set(player, selected_floor)
        return true
    else
        return false
    end
end


--- Clean up cache after a config change that potentially deleted objects
---@param player LuaPlayer
function _context.validate(player)
    local player_table = lib.globals.player_table(player)
    local context = player_table.context
    local cache = context.cache

    -- Using existance in OBJECT_INDEX is valid here as this is only called after a reload,
    -- which implies that only objects that are still in used have been re-indexed.

    if not OBJECT_INDEX[cache.district] then cache.district = nil end

    for district_id, factory_cache in pairs(cache.factories) do
        if not OBJECT_INDEX[district_id] then cache.factories[district_id] = nil end

        if not OBJECT_INDEX[factory_cache.factory] then factory_cache.factory = nil end

        for factory_id, floor_id in pairs(factory_cache.floors) do
            if not (OBJECT_INDEX[factory_id] and OBJECT_INDEX[floor_id]) then
                factory_cache.floors[factory_id] = nil
            end
        end
    end

    if not (context.object_id and OBJECT_INDEX[context.object_id]) then
        _context.set(player, player_table.realm.first)
    end
end

return _context

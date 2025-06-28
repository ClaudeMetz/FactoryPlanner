local _context = {}

---@class ContextTable
---@field object_id ObjectID?
---@field cache ContextCache

---@class ContextCache
---@field district ObjectID? DistrictID
---@field factories { [ObjectID]: ContextFactories } DistrictID ->

---@class ContextFactories
---@field factory ObjectID? FactoryID
---@field floors { [ObjectID]: ObjectID } FactoryID -> FloorID

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


---@param player LuaPlayer
---@param class string
---@return ContextObject?
--- Gets the given object type by going up the hierarchy from the current context
function _context.get(player, class)
    local player_table = util.globals.player_table(player)
    local object = OBJECT_INDEX[player_table.context.object_id]

    repeat
        if object.class == class then
            return object --[[@as ContextObject]]
        end
        object = object.parent
    until object == nil

    return nil
end

---@param player LuaPlayer
---@param object ContextObject
---@param force_district boolean?
--- Restores the appropriate floor from context cache depending on the given object
--- This covers the happy path, extra care needs to be taken when objects were removed
function _context.set(player, object, force_district)
    local context = util.globals.player_table(player).context
    local cache = context.cache

    if object.class == "District" then
        -- Update cache
        cache.district = object.id

        if force_district then context.object_id = object.id; return end

        -- Set lowest-down existing object
        local factory_cache = cache.factories[object.id]
        if factory_cache and factory_cache.factory then object = OBJECT_INDEX[factory_cache.factory]
        elseif object.first then object = OBJECT_INDEX[object.first.id]
        else context.object_id = object.id; return end
    end

    if object.class == "Factory" then
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

    if object.class == "Floor" then
        -- Needs to be done first so .get() can work
        context.object_id = object.id

        -- Update cache
        -- Uses .get() method to move up through eventual subfloors
        local factory = _context.get(player, "Factory")  --[[@as Factory]]
        local floors_cache = cache.factories[factory.parent.id].floors
        -- The above cache is guaranteed to exist to be able to get here
        floors_cache[factory.id] = object.id
    end
end

---@param player LuaPlayer
---@param object (District | Factory)
---@return ContextObject? replacement
--- Cleans up after the given object was removed and tries to find a replacement
function _context.remove(player, object)
    local cache = util.globals.player_table(player).context.cache

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
    local filter = (object.class == "Factory") and { archived = object.archived } or {}

    local previous = object.parent:find(filter, object["previous"], "previous")
    if previous then return previous end
    local next = object.parent:find(filter, object["next"], "next")
    if next then return next end

    return nil  -- none found, caller needs to sort it out
end


---@alias FloorDestination "up" | "top"

---@param player LuaPlayer
---@param destination FloorDestination
---@return boolean success
function _context.ascend_floors(player, destination)
    local floor = _context.get(player, "Floor")  --[[@as Floor?]]
    if floor == nil then return false end

    local selected_floor = nil
    if destination == "up" and floor.level > 1 then
        selected_floor = floor.parent
    elseif destination == "top" then
        local top_floor = _context.get(player, "Factory").top_floor
        if top_floor ~= floor then selected_floor = top_floor end
    end

    if selected_floor ~= nil then
        -- Reset the subfloor we moved from if it doesn't have any additional recipes
        if floor:count() == 1 then floor.parent:replace(floor, floor.first) end

        _context.set(player, selected_floor)
        return true
    else
        return false
    end
end


---@param player LuaPlayer
--- Clean up cache after a config change that potentially deleted objects
function _context.validate(player)
    local player_table = util.globals.player_table(player)
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

local _context = {}

---@class ContextTable
---@field object_id ObjectID?
---@field cache ContextCache

---@class ContextCache
---@field main ObjectID?
---@field archive ObjectID?
---@field factory { [ObjectID]: ObjectID } FactoryID -> FloorID

---@alias ContextObject (District | Factory | Floor)

---@param player LuaPlayer
function _context.init(player)
    local player_table = util.globals.player_table(player)
    player_table.context = {
        object_id = player_table.district.id,
        cache = {
            main = nil,
            archive = nil,
            factory = {}
        }
    }
end

---@param player LuaPlayer
---@param class string
---@return ContextObject?
function _context.get(player, class)
    local player_table = util.globals.player_table(player)
    local object_id  = player_table.context.object_id

    if object_id == nil then return error("object_id not set") end
    local object = OBJECT_INDEX[object_id]

    repeat
        if object.class == class then return object --[[@as ContextObject]] end
        object = object.parent
    until object == nil

    return nil
end

---@param player LuaPlayer
---@param archive boolean
--- Sets the context to any valid object, with the District as fallback
function _context.set_default(player, archive)
    local player_table = util.globals.player_table(player)
    local cache = player_table.context.cache

    if archive then
        if cache.archive then
            _context.set(player, OBJECT_INDEX[cache.archive])
        else
            local factory = player_table.district:find({ archived = true })
            if factory then _context.set(player, factory)
            else archive = false end  -- try non-archive
        end
    end

    if not archive then
        if cache.main then
            _context.set(player, OBJECT_INDEX[cache.main])
        else
            local factory = player_table.district:find({ archived = false })
            if factory then _context.set(player, factory)
            else player_table.context.object_id = player_table.district.id end
        end
    end
end

---@param player LuaPlayer
---@param object Factory | Floor
function _context.set(player, object)
    local context = util.globals.player_table(player).context
    local cache = context.cache

    if object.class == "Factory" then
        if object.archived then cache.archive = object.id
        else cache.main = object.id end

        if cache.factory[object.id] then context.object_id = cache.factory[object.id].id
        else context.object_id = object.top_floor.id end

    elseif object.class == "Floor" then
        context.object_id = object.id
        cache.factory[object.parent.id] = object.id

        if object.parent.archived then cache.archive = object.parent.id
        else cache.main = object.parent.id end
    end
end

---@param player LuaPlayer
---@param object Factory
---@param archived boolean?
function _context.set_adjacent(player, object, archived)
    if archived == nil then archived = object.archived end
    local filter = { archived = archived }

    local previous = object.parent:find(filter, "previous", object)
    if previous then _context.set(player, previous); return end
    local next = object.parent:find(filter, "next", object)
    if next then _context.set(player, next); return end

    _context.set_default(player, false)
end

---@param player LuaPlayer
---@param object Factory | Floor
function _context.remove(player, object)
    local cache = util.globals.player_table(player).context.cache

    if object.class == "Factory" then
        if cache.main == object.id then cache.main = nil end
        if cache.archive == object.id then cache.archive = nil end
    elseif object.class == "Floor" then
        if cache.factory[object.parent.id] == object.id then
            cache.factory[object.parent.id] = nil
        end
    end
end

---@param player LuaPlayer
function _context.validate(player)
    local context = util.globals.player_table(player).context
    local cache = context.cache

    if not OBJECT_INDEX[cache.main] then cache.main = nil end
    if not OBJECT_INDEX[cache.archive] then cache.archive = nil end

    for factory_id, floor_id in pairs(cache.factory) do
        if not (OBJECT_INDEX[factory_id] and OBJECT_INDEX[floor_id]) then
            cache.factory[factory_id] = nil
        end
    end

    if not context.object_id then return end
    if not OBJECT_INDEX[context.object_id] then
        context.object_id = nil
        _context.set_default(player, false)
    end
end

return _context

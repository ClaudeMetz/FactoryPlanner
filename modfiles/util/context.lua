local _context = {}

---@class Context
---@field factory FPFactory
---@field subfactory FPSubfactory?
---@field floor FPFloor?

-- Creates a blank context referencing which part of the Factory is currently displayed
---@param player LuaPlayer
---@return Context context
function _context.create(player)
    return {
        factory = global.players[player.index].factory,
        subfactory = nil,
        floor = nil
    }
end

-- Updates the context to match the newly selected factory
---@param player LuaPlayer
---@param factory FPFactory
function _context.set_factory(player, factory)
    local context = data_util.context(player)
    context.factory = factory
    local subfactory = factory.selected_subfactory
        or Factory.get_by_gui_position(factory, "Subfactory", 1)  -- might be nil
    util.context.set_subfactory(player, subfactory)
end

-- Updates the context to match the newly selected subfactory
---@param player LuaPlayer
---@param subfactory FPSubfactory?
function _context.set_subfactory(player, subfactory)
    local context = data_util.context(player)
    context.factory.selected_subfactory = subfactory
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
end

-- Updates the context to match the newly selected floor
---@param player LuaPlayer
---@param floor FPFloor
function _context.set_floor(player, floor)
    local context = data_util.context(player)
    context.subfactory.selected_floor = floor
    context.floor = floor
end

-- Changes the context to the floor indicated by the given destination
---@param player LuaPlayer
---@param destination "up" | "down"
---@return boolean success
function _context.change_floor(player, destination)
    local context = data_util.context(player)
    local subfactory, floor = context.subfactory, context.floor
    if subfactory == nil or floor == nil then return false end

    local selected_floor = nil  ---@type FPFloor
    if destination == "up" and floor.level > 1 then
        selected_floor = floor.origin_line.parent
    elseif destination == "top" then
        selected_floor = Subfactory.get(subfactory, "Floor", 1)
    end

    if selected_floor ~= nil then
        util.context.set_floor(player, selected_floor)
        -- Reset the subfloor we moved from if it doesn't have any additional recipes
        if Floor.count(floor, "Line") < 2 then Floor.reset(floor) end
    end
    return (selected_floor ~= nil)
end

return _context

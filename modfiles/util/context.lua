local _context = {}

--[[ -- Changes the context to the floor indicated by the given destination
---@param player LuaPlayer
---@param destination "up" | "down"
---@return boolean success
function _context.change_floor(player, destination)
    local context = util.globals.context(player)
    local subfactory, floor = context.subfactory, context.floor
    if subfactory == nil or floor == nil then return false end

    local selected_floor = nil  ---@type Floor
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
end ]]


---@param player LuaPlayer
---@param class string
---@return Object?
function _context.get(player, class)
    local ui_state = util.globals.ui_state(player)
    if not ui_state.context then return nil end
    local object = OBJECT_INDEX[ui_state.context]

    repeat
        if object.class == class then return object end
        object = object.parent
    until object == nil

    return nil
end

---@param player LuaPlayer
---@param object Object
function _context.set(player, object)
    util.globals.ui_state(player).context = object.id
end

return _context

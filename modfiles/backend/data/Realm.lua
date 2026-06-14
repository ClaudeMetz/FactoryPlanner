local Object = require("backend.data.Object")
local District = require("backend.data.District")

---@class Realm: Object, ObjectMethods
---@field class "Realm"
---@field first District
local Realm = Object.methods()
Realm.__index = Realm
script.register_metatable("Realm", Realm)

---@param district District?
---@return Realm
local function init(district)
    local object = Object.init({
        first = nil
    }, "Realm", Realm)  --[[@as Realm]]
    object:insert(district or District.init())  -- one always exists
    return object
end


function Realm:index()
    OBJECT_INDEX[self.id] = self
    for district in self:iterator() do district:index() end
end


---@param district District
---@param relative_object District?
---@param direction NeighbourDirection?
function Realm:insert(district, relative_object, direction)
    district.parent = self
    self:_insert(district, relative_object, direction)
end

---@param district District
function Realm:remove(district)
    -- Delete factories separately so they can clean up any nth_tick events
    for factory in district:iterator() do district:remove(factory) end
    district.parent = nil
    self:_remove(district)
end

---@param district District
---@param direction NeighbourDirection
---@param spots integer?
function Realm:shift(district, direction, spots)
    self:_shift(district, direction, spots)
end


---@param filter ObjectFilter
---@param pivot District?
---@param direction NeighbourDirection?
---@return District? district
function Realm:find(filter, pivot, direction)
    return self:_find(filter, pivot, direction)  --[[@as District?]]
end


---@param filter ObjectFilter?
---@param pivot District?
---@param direction NeighbourDirection?
---@return fun(): District?
function Realm:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot District?
---@return number count
function Realm:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


---@param starting_tick Tick
---@param player LuaPlayer
function Realm:schedule_solver_updates(starting_tick, player)
    local running_tick = starting_tick
    for district in self:iterator() do
        -- District returns the last tick it registered for
        running_tick = district:schedule_solver_updates(running_tick, player)
        running_tick = running_tick + MAGIC_NUMBERS.factory_solver_update_delay
    end
end


--- The realm can't be invalid, this just cleanly validates Districts
function Realm:validate()
    self:_validate()
end

return {init = init}

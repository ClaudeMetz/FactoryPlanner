local Object = require("backend.data.Object")
local District = require("backend.data.District")

---@class Realm: Object, ObjectMethods
---@field class "Realm"
---@field first District
local Realm = Object.methods()
Realm.__index = Realm
script.register_metatable("Realm", Realm)

---@return Realm
local function init()
    local object = Object.init({
        first = District.init()  -- one always exists
    }, "Realm", Realm)  --[[@as Realm]]
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
    district.parent = nil
    self:_remove(district)
end

---@param district District
---@param direction NeighbourDirection
---@param spots integer?
function Realm:shift(district, direction, spots)
    self:_shift(district, direction, spots)
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


--- The realm can't be invalid, this just cleanly validates the factories
function Realm:validate()
    self:_validate()
end


return {init = init}

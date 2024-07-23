local Object = require("backend.data.Object")

---@class District: Object, ObjectMethods
---@field class "District"
---@field parent Realm
---@field next District?
---@field previous District?
---@field name string
---@field first Factory?
local District = Object.methods()
District.__index = District
script.register_metatable("District", District)

---@param name string?
---@return District
local function init(name)
    local object = Object.init({
        name = name or "New District",
        first = nil
    }, "District", District)  --[[@as District]]
    return object
end


function District:index()
    OBJECT_INDEX[self.id] = self
    for factory in self:iterator() do factory:index() end
end


---@param factory Factory
---@param relative_object Factory?
---@param direction NeighbourDirection?
function District:insert(factory, relative_object, direction)
    factory.parent = self
    self:_insert(factory, relative_object, direction)
end

---@param factory Factory
function District:remove(factory)
    factory.parent = nil
    self:_remove(factory)
end

---@param factory Factory
---@param direction NeighbourDirection
---@param spots integer?
function District:shift(factory, direction, spots)
    local filter = { archived = factory.archived }
    self:_shift(factory, direction, spots, filter)
end


---@param filter ObjectFilter
---@param pivot Factory?
---@param direction NeighbourDirection?
---@return Factory? factory
function District:find(filter, pivot, direction)
    return self:_find(filter, pivot, direction)  --[[@as Factory?]]
end


---@param filter ObjectFilter?
---@param pivot Factory?
---@param direction NeighbourDirection?
---@return fun(): Factory?
function District:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot Factory?
---@return number count
function District:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


--- Districts can't be invalid, this just cleanly validates the factories
function District:validate()
    self:_validate()
end

return {init = init}

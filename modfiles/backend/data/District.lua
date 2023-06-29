local Object = require("backend.data.Object")

---@class District: Object, ObjectMethods
---@field first_factory Factory?
local District = Object.methods()
District.__index = District
script.register_metatable("District", District)

---@return District
local function init()
    local object = Object.init({
        first_factory = nil
    }, "District", District)  --[[@as District]]
    return object
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
    self:_remove(factory)
    OBJECT_INDEX[factory.id] = nil
end

---@param factory Factory
---@param direction NeighbourDirection
---@param spots integer?
function District:shift(factory, direction, spots)
    local filter = { archived = factory.archived }
    self:_shift(factory, direction, spots, filter)
end


---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot Factory?
---@return Factory? factory
function District:find(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_factory)
    return self:_find(pivot_object, filter, direction)  --[[@as Factory?]]
end


---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot Factory?
---@return function iterator
function District:iterator(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_factory)
    return self:_iterator(pivot_object, filter, direction)
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot Factory?
---@return number count
function District:count(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_factory)
    return self:_count(pivot_object, filter, direction)
end


--- Districts can't be invalid, this just cleanly validates the factories
function District:validate()
    self:_validate(self.first_factory)
end

return init

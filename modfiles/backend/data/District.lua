local Object = require("backend.data.Object")

---@class District: Object, ObjectMethods
---@field class "District"
---@field parent Realm
---@field next District?
---@field previous District?
---@field name string
---@field location_proto FPLocationPrototype
---@field first Factory?
---@field power number
---@field emissions number
---@field needs_refresh boolean
local District = Object.methods()
District.__index = District
script.register_metatable("District", District)

---@param name string?
---@return District
local function init(name)
    local object = Object.init({
        name = name or "New District",
        location_proto = defaults.get_fallback("locations").proto,
        first = nil,

        --[[ products = SimpleItems.init(),
        byproducts = SimpleItems.init(),
        ingredients = SimpleItems.init(), ]]
        power = 0,
        emissions = 0,

        needs_refresh = false
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
    -- Make sure the nth_tick handlers are cleaned up
    if factory.tick_of_deletion then util.nth_tick.cancel(factory.tick_of_deletion) end
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


-- Updates the power, emissions and items of this District if requested
function District:refresh()
    --[[ if not self.needs_refresh then return end
    self.needs_refresh = false

    self.power = 0
    self.emissions = 0
    self.products:clear()
    self.byproducts:clear()
    self.ingredients:clear()

    for factory in self:iterator({archived=false, valid=true}) do
        self.power = self.power + factory.top_floor.power
        self.emissions = self.emissions + factory.top_floor.emissions

        local product_items = SimpleItems.init()
        for product in factory:iterator() do
            product_items:insert({class="SimpleItem", proto=product.proto, amount=product.amount})
        end
        self.products:add_multiple(product_items)

        self.byproducts:add_multiple(factory.top_floor.byproducts)
        self.ingredients:add_multiple(factory.top_floor.ingredients)
    end ]]
end


---@return boolean valid
function District:validate()
    self:_validate()  -- invalid factories don't make the district invalid

    -- Invalid locations are just replaced with valid ones to make the district valid
    self.location_proto = prototyper.util.validate_prototype_object(self.location_proto, nil)
    if self.location_proto.simplified then
        self.location_proto = defaults.get_fallback("locations").proto
    end

    return true  -- always makes itself valid
end

return {init = init}

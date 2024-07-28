local Object = require("backend.data.Object")
local SimpleItems = require("backend.data.SimpleItems")

---@class District: Object, ObjectMethods
---@field class "District"
---@field parent Realm
---@field next District?
---@field previous District?
---@field name string
---@field location_proto FPLocationPrototype
---@field products SimpleItems
---@field byproducts SimpleItems
---@field ingredients SimpleItems
---@field first Factory?
---@field power number
---@field emissions Emissions
---@field needs_refresh boolean
local District = Object.methods()
District.__index = District
script.register_metatable("District", District)

---@param name string?
---@param location string?
---@return District
local function init(name, location)
    local object = Object.init({
        name = name or "New District",
        location_proto = prototyper.util.find_prototype("locations", location or "nauvis"),
        products = SimpleItems.init(),
        byproducts = SimpleItems.init(),
        ingredients = SimpleItems.init(),
        first = nil,

        power = 0,
        emissions = {},
        needs_refresh = false
    }, "District", District)  --[[@as District]]
    return object
end


function District:index()
    OBJECT_INDEX[self.id] = self
    for factory in self:iterator() do factory:index() end
    self.products:index()
    self.byproducts:index()
    self.ingredients:index()
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


-- Updates the power, emissions and items of this District if requested
function District:refresh()
    if not self.needs_refresh then return end
    self.needs_refresh = false

    self.power = 0
    self.emissions = {}
    self.products:clear()
    self.byproducts:clear()
    self.ingredients:clear()

    for factory in self:iterator() do
        if factory.archived then goto continue end

        self.power = self.power + factory.top_floor.power
        for name, amount in pairs(factory.top_floor.emissions) do
            self.emissions[name] = (self.emissions[name] or 0) + amount
        end

        local product_items = SimpleItems.init()
        for product in factory:iterator() do
            product_items:insert({class="SimpleItem", proto=product.proto, amount=product.amount})
        end
        self.products:add_multiple(product_items, factory.timescale)

        self.byproducts:add_multiple(factory.top_floor.byproducts, factory.timescale)
        self.ingredients:add_multiple(factory.top_floor.ingredients, factory.timescale)

        :: continue ::
    end
end


--- Districts can't be invalid, this just cleanly validates the factories
function District:validate()
    self:_validate()
end

return {init = init}

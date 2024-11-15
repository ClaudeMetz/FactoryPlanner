local Object = require("backend.data.Object")
local DistrictItem = require("backend.data.DistrictItem")

---@class DistrictItemSet: Object, ObjectMethods
---@field class "DistrictItemSet"
---@field first DistrictItem?
---@field map { [FPItemPrototype]: DistrictItem }
local DistrictItemSet = Object.methods()
DistrictItemSet.__index = DistrictItemSet
script.register_metatable("DistrictItemSet", DistrictItemSet)

---@return DistrictItemSet
local function init()
    local object = Object.init({
        first = nil,
        map = {}
    }, "DistrictItemSet", DistrictItemSet)  --[[@as DistrictItemSet]]
    return object
end


function DistrictItemSet:index()
    OBJECT_INDEX[self.id] = self
    for district_item in self:iterator() do district_item:index() end
end


---@param items SimpleItem[]
---@param mode DistrictItemMode
function DistrictItemSet:add_items(items, mode)
    for _, item in pairs(items) do
        local district_item = self.map[item.proto]

        if not district_item then
            district_item = DistrictItem.init(item.proto)
            district_item.parent = self
            self:_insert(district_item)
            self.map[district_item.proto] = district_item
        end

        district_item:add(item.amount, mode)
    end
end


---@param district_item DistrictItem
function DistrictItemSet:remove(district_item)
    district_item.parent = nil
    self:_remove(district_item)
end


---@param filter ObjectFilter?
---@param pivot DistrictItem?
---@param direction NeighbourDirection?
---@return fun(): DistrictItem?
function DistrictItemSet:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end


function DistrictItemSet:diff()
    for item in self:iterator() do
        local diff = item.production.amount - item.consumption.amount
        item.overall = (diff > 0) and "production" or "consumption"
        item.abs_diff = math.abs(diff)

        if item.abs_diff < MAGIC_NUMBERS.margin_of_error then self:remove(item) end
    end
end

-- Sorts (awkwardly) based on type first ("item" before "fluid") and then amount
local function item_compare(a, b)
    local a_type, b_type = a.proto.type, b.proto.type
    if a_type < b_type then return true
    elseif a_type > b_type then return false
    elseif a.abs_diff < b.abs_diff then return true
    elseif a.abs_diff > b.abs_diff then return false end
    return false
end

function DistrictItemSet:sort()
    local next_object = self.first
    self.first = nil  -- clear to re-insert into below

    while next_object ~= nil do
        local current_object = next_object
        next_object = next_object.next

        local inserted = false  -- TODO drop items that average out to 0
        for object in self:iterator() do
            if item_compare(object, current_object) then
                self:_insert(current_object, object, "previous")
                inserted = true
                break
            end
        end
        if not inserted then  -- first or last element
            self:_insert(current_object)
        end
    end
end


function DistrictItemSet:clear()
    self.first = nil
    self.map = {}
end

return {init = init}

local Object = require("backend.data.Object")

---@alias DistrictItemMode "production" | "consumption"

---@class DistrictItemData
---@field amount number

---@class DistrictItem: Object, ObjectMethods
---@field class "DistrictItem"
---@field proto FPItemPrototype
---@field production DistrictItemData
---@field consumption DistrictItemData
local DistrictItem = Object.methods()
DistrictItem.__index = DistrictItem
script.register_metatable("DistrictItem", DistrictItem)

---@param proto FPItemPrototype
---@return DistrictItem
local function init(proto)
    local object = Object.init({
        proto = proto,
        production = {amount=0},
        consumption = {amount=0},

        overall = nil,
        abs_diff = 0
    }, "DistrictItem", DistrictItem)  --[[@as DistrictItem]]
    return object
end


function DistrictItem:index()
    OBJECT_INDEX[self.id] = self
end


---@param amount number
---@param mode DistrictItemMode
function DistrictItem:add(amount, mode)
    self[mode].amount = self[mode].amount + amount
end

return {init = init}

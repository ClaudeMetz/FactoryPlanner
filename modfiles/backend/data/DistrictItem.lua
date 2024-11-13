local Object = require("backend.data.Object")

---@class DistrictItem: Object, ObjectMethods
---@field class "DistrictItem"
---@field proto FPItemPrototype
---@field amount number
---@field converse_amount number
local DistrictItem = Object.methods()
DistrictItem.__index = DistrictItem
script.register_metatable("DistrictItem", DistrictItem)

---@param proto FPItemPrototype
---@param amount number
---@return DistrictItem
local function init(proto, amount)
    local object = Object.init({
        proto = proto,
        amount = amount,  -- amount filled in by the factories
        converse_amount = 0  -- amount of this item in converse category
    }, "DistrictItem", DistrictItem)  --[[@as DistrictItem]]
    return object
end


function DistrictItem:index()
    OBJECT_INDEX[self.id] = self
end

return {init = init}

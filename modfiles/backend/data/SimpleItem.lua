local Object = require("backend.data.Object")

---@alias SimpleItemCategory "product" | "byproduct" | "ingredient"

---@class SimpleItem: Object, ObjectMethods
---@field class "SimpleItem"
---@field parent Floor
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number
local SimpleItem = Object.methods()
SimpleItem.__index = SimpleItem
script.register_metatable("SimpleItem", SimpleItem)

---@param proto FPItemPrototype
---@param amount number?
---@return SimpleItem
local function init(proto, amount)
    local object = Object.init({
        proto = proto,
        amount = amount or 0,
        satisfied_amount = 0
    }, "SimpleItem", SimpleItem)  --[[@as SimpleItem]]
    return object
end


function SimpleItem:index()
    OBJECT_INDEX[self.id] = self
end

function SimpleItem:cleanup()
    OBJECT_INDEX[self.id] = nil
end

-- SimpleItems don't need any validation or repair, they are just removed and re-calculated

return {init = init}

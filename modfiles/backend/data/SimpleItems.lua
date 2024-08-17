local Object = require("backend.data.Object")

---@alias SimpleItemCategory "product" | "byproduct" | "ingredient"

--- Not actually a class
---@class SimpleItem
---@field class "SimpleItem"
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number?

---@class SimpleItems: Object, ObjectMethods
---@field class "SimpleItems"
---@field parent LineObject
---@field items SimpleItem[]
local SimpleItems = Object.methods()
SimpleItems.__index = SimpleItems
script.register_metatable("SimpleItems", SimpleItems)

---@return SimpleItems
local function init()
    local object = Object.init({
        items = {}
    }, "SimpleItems", SimpleItems)  --[[@as SimpleItems]]
    return object
end


function SimpleItems:index()
    OBJECT_INDEX[self.id] = self
end


---@param item SimpleItem
function SimpleItems:insert(item)
    table.insert(self.items, item)
end

---@param simple_items SimpleItems
---@param divisor number
function SimpleItems:add_multiple(simple_items)
    local dict = {}
    for _, item in pairs(self.items) do
        dict[item.proto] = item
    end

    for _, item in pairs(simple_items.items) do
        local existing = dict[item.proto]
        if existing then
            existing.amount = existing.amount + item.amount
        else
            table.insert(self.items, {class="SimpleItem", proto=item.proto, amount=item.amount})
        end
    end
end

function SimpleItems:clear()
    self.items = {}
end


---@param proto FPItemPrototype
---@return SimpleItem? simple_item
function SimpleItems:find(proto)
    for _, simple_item in pairs(self.items) do
        if simple_item.proto == proto then return simple_item end
    end
end

---@param reverse boolean?
---@return fun(): integer?, SimpleItem?
function SimpleItems:iterator(reverse)
    local i = (reverse) and #self.items+1 or 0
    local step = (reverse) and -1 or 1
    return function()
        i = i + step; local next = self.items[i]
        if next then return i, next end
    end
end

---@return number count
function SimpleItems:count()
    return #self.items
end


-- SimpleItems don't need any validation or repair, they are just cleared and re-calculated

return {init = init}

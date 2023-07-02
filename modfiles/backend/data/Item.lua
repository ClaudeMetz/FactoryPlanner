local Object = require("backend.data.Object")

-- TODO might move this to the solver at some point
-- Not a class, just a simple data structure for items
-- that are not user data, just solver results
---@class SimpleItem
---@field proto FPItemPrototype
---@field amount number


---@class RequiredAmount
---@field defined_by "amount" | "belts" | "lanes"
---@field amount number
---@field belt_proto FPBeltPrototype

---@class Item: Object, ObjectMethods
---@field class "Item"
---@field parent Factory | Line
---@field proto FPItemPrototype
local Item = Object.methods()
Item.__index = Item
script.register_metatable("Item", Item)

---@return Item
local function init(proto)
    local object = Object.init({
        proto = proto,
    }, "Item", Item)  --[[@as Item]]
    return object
end


---@class PackedItem: PackedObject
---@field class "Item"
---@field proto FPPackedPrototype

---@return PackedItem packed_self
function Item:pack()
    return {}
end

---@param packed_self PackedItem
---@return Item Item
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto)
    return unpacked_self
end

---@return boolean valid
function Item:validate()
    return true
end

---@param player LuaPlayer
function Item:repair(player)

end

return {init = init, unpack = unpack}

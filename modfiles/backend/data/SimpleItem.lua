--- Not an real Object, but has a metatable
---@class SimpleItem
---@field class "SimpleItem"
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number?
---@field parent LineObject?
local SimpleItem = {}
SimpleItem.__index = SimpleItem
script.register_metatable("SimpleItem", SimpleItem)

---@param parent LineObject?
---@param proto FPItemPrototype
---@param amount number?
---@return SimpleItem
local function init(parent, proto, amount)
    ---@diagnostic disable-next-line: missing-fields
    local item = {
        proto = proto,
        class = "SimpleItem",
        amount = amount or 0,
        satisfied_amount = nil,
        parent = parent  -- can be nil
    }  ---@type SimpleItem
    setmetatable(item, SimpleItem)
    return item
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function SimpleItem:paste(object)
    if object.class == "SimpleItem" or object.class == "Fuel" then
        ---@cast object.proto -nil

        -- Only pasting on a line item is allowed
        if not self.parent or self.parent.class ~= "Line" then
            return false, "incompatible"
        end
        -- Only pasting on fluids is allowed
        if object.proto.type ~= "fluid" or self.proto.type ~= "fluid" then
            return false, "incompatible"
        end

        if object.class == "SimpleItem" then  ---@cast object SimpleItem
            if object.proto.base_name ~= self.proto.name then return false, "incompatible" end
            if not object.proto.temperature then return false, "incompatible" end
            if not self.parent.recipe:is_temperature_valid(self.proto, object.proto.temperature) then
                return false, "incompatible"
            end
            self.parent.recipe:set_temperature(self.proto.name, object.proto.temperature)
        else  ---@cast object Fuel
            if object.proto.name ~= self.proto.name then return false, "incompatible" end
            if not object.temperature then return false, "incompatible" end
            if not self.parent.recipe:is_temperature_valid(self.proto, object.temperature) then
                return false, "incompatible"
            end
            self.parent.recipe:set_temperature(self.proto.name, object.temperature)
        end

        return true, nil
    else
        return false, "incompatible_class"
    end
end

---@class PackedSimpleItem
---@field class "SimpleItem"
---@field proto FPPackedPrototype
---@field amount number

---@return PackedSimpleItem
function SimpleItem:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        amount = self.amount
    }
end

-- Helper functions to pack up Floor or Line products, byproducts and ingredients
---@param items SimpleItem[]
---@return PackedSimpleItem[]
local function pack_items(items)
    local packed_items = {}  ---@type PackedSimpleItem[]
    for _, item in ipairs(items) do table.insert(packed_items, item:pack()) end
    return packed_items
end


return {init = init, pack_items = pack_items}

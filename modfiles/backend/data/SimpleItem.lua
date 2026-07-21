---@class SimpleItem not an `Object`
---@field class "SimpleItem"
---@field proto FPItemPrototype
---@field amount number
---@field satisfied_amount number?
---@field parent LineObject?
local SimpleItem = {}
SimpleItem.__index = SimpleItem


---@param parent LineObject?
---@param proto FPItemPrototype
---@param amount number?
---@return SimpleItem
function SimpleItem:init(parent, proto, amount)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        proto = proto,
        class = "SimpleItem",
        amount = amount or 0,
        satisfied_amount = nil,
        parent = parent  -- can be nil
    }  ---@type SimpleItem
    setmetatable(o, self)
    return o
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function SimpleItem:paste(object)
    if object.class == "SimpleItem" or object.class == "Fuel" then
        ---@diagnostic disable-next-line: cast-type-mismatch
        ---@cast object SimpleItem | Fuel

        -- Only pasting on a line item is allowed
        if not self.parent or self.parent.class ~= "Line" then
            return false, "incompatible"
        end

        -- Only pasting on fluids is allowed
        if object.proto.type ~= "fluid" or self.proto.type ~= "fluid" then
            return false, "incompatible"
        end

        -- SimpleItems will always be a fluid with temperature
        if object.class == "SimpleItem" then  ---@cast object SimpleItem
            if object.proto.base_name ~= self.proto.name then return false, "incompatible" end
            self.parent.recipe.temperatures[self.proto.name] = object.proto.temperature
        else  ---@cast object Fuel
            if object.proto.name ~= self.proto.name then return false, "incompatible" end
            self.parent.recipe.temperatures[self.proto.name] = object.temperature
        end

        return true, nil
    else
        return false, "incompatible_class"
    end
end


return SimpleItem

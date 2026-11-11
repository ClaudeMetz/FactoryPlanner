--- Not an real Object, but has a metatable
---@class SimpleItem
---@field class "SimpleItem"
---@field proto FPItemPrototype
---@field quality_proto FPQualityPrototype?
---@field amount number
---@field target_amount number? Contribution to the containing floor's target
---@field required_amount number? Floor production or consumption required by its parent
---@field parent LineObject?
local SimpleItem = {}
SimpleItem.__index = SimpleItem
script.register_metatable("SimpleItem", SimpleItem)

---@param parent LineObject?
---@param proto FPItemPrototype
---@param quality_proto FPQualityPrototype?
---@param amount number?
---@return SimpleItem
local function init(parent, proto, quality_proto, amount)
    ---@diagnostic disable-next-line: missing-fields
    local item = {
        proto = proto,
        quality_proto = quality_proto,  -- can be nil
        class = "SimpleItem",
        amount = amount or 0,
        target_amount = nil,
        required_amount = nil,
        parent = parent  -- can be nil
    }  ---@type SimpleItem
    setmetatable(item, SimpleItem)
    return item
end


---@return number
function SimpleItem:get_remaining_amount()
    local target_amount = self.target_amount or 0
    local tolerance = math.max(self.amount, target_amount) * MAGIC_NUMBERS.margin_of_error
    local difference = self.amount - target_amount
    return difference > tolerance and difference or 0
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function SimpleItem:paste(object)
    if object.class == "FactoryItem" or object.class == "SimpleItem" or object.class == "Fuel" then
        ---@cast object.proto -nil

        -- Only pasting on a line item is allowed
        if not self.parent or self.parent.class ~= "Line" then
            return false, "incompatible"
        end
        local line = self.parent  ---@as Line
        -- Only pasting on fluids is allowed
        if object.proto.type ~= "fluid" or self.proto.type ~= "fluid" then
            return false, "incompatible"
        end

        if object.class ~= "Fuel" then  ---@cast object.proto FPItemPrototype
            if object.proto.base_name ~= self.proto.name then return false, "incompatible" end
            if not object.proto.temperature then return false, "incompatible" end
            if not line.recipe:is_temperature_valid(self.proto, object.proto.temperature) then
                return false, "incompatible"
            end
            line.recipe:set_temperature(self.proto.name, object.proto.temperature)
        else  ---@cast object Fuel
            if object.proto.name ~= self.proto.name then return false, "incompatible" end
            if not object.temperature then return false, "incompatible" end
            if not line.recipe:is_temperature_valid(self.proto, object.temperature) then
                return false, "incompatible"
            end
            line.recipe:set_temperature(self.proto.name, object.temperature)
        end

        return true, nil
    else
        return false, "incompatible_class"
    end
end

---@class PackedSimpleItem
---@field class "SimpleItem"
---@field proto FPPackedPrototype
---@field quality_proto FPPackedPrototype?
---@field amount number
---@field target_amount number?
---@field required_amount number?

---@return PackedSimpleItem
function SimpleItem:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        quality_proto = self.quality_proto and prototyper.util.simplify_prototype(self.quality_proto),
        amount = self.amount,
        target_amount = self.target_amount,
        required_amount = self.required_amount,
    }
end

---@param packed_self PackedSimpleItem
---@return SimpleItem?  -- discard if invalid
local function unpack(packed_self)
    local item_proto = prototyper.util.validate_prototype_object(packed_self.proto, "type")
    local valid = not item_proto.simplified
    ---@cast item_proto FPItemPrototype

    local quality_proto = packed_self.quality_proto and prototyper.util.validate_prototype_object(packed_self.quality_proto)
    quality_proto = (quality_proto and not quality_proto.simplified) and quality_proto or nil
    ---@cast quality_proto FPQualityPrototype?

    local unpacked_self = init(nil, item_proto, quality_proto, packed_self.amount)
    unpacked_self.target_amount = packed_self.target_amount
    unpacked_self.required_amount = packed_self.required_amount

    return valid and unpacked_self or nil
end

-- Helper functions to pack up Floor or Line products, byproducts and ingredients
---@param items SimpleItem[]
---@return PackedSimpleItem[]
local function pack_items(items)
    local packed_items = {}  ---@type PackedSimpleItem[]
    for _, item in ipairs(items) do table.insert(packed_items, item:pack()) end
    return packed_items
end

---@param packed_items PackedSimpleItem[]
---@return SimpleItem[]
local function unpack_items(packed_items)
    local items = {}  ---@type SimpleItem[]
    for _, packed_item in ipairs(packed_items) do
        local item = unpack(packed_item)
        if item then table.insert(items, item) end
    end
    return items
end


return {init = init, unpack = unpack, pack_items = pack_items, unpack_items = unpack_items}

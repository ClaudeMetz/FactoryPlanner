local Object = require("backend.data.Object")

---@alias ProductDefinedBy "amount" | "belts" | "lanes"

---@class TLProduct: Object, ObjectMethods
---@field class "TLProduct"
---@field parent Factory
---@field proto FPItemPrototype | FPPackedPrototype
---@field defined_by ProductDefinedBy
---@field required_amount number
---@field belt_proto (FPBeltPrototype | FPPackedPrototype)?
---@field amount number
local TLProduct = Object.methods()
TLProduct.__index = TLProduct
script.register_metatable("TLProduct", TLProduct)

---@param proto FPItemPrototype | FPPackedPrototype
---@return TLProduct
local function init(proto)
    local object = Object.init({
        proto = proto,
        defined_by = "amount",
        required_amount = 0,  -- always per second
        belt_proto = nil,

        amount = 0  -- the amount satisfied by the solver
    }, "TLProduct", TLProduct)  --[[@as TLProduct]]
    return object
end


---@return TLProduct
local function initDummy()
    local object = Object.init({
        proto = {
            name="",
            category="item",
            data_type="items",
            simplified=true
        }, --[[@as FPPackedPrototype]]
        defined_by = "amount",
        required_amount = 0,
        belt_proto = nil,
        amount = 0,
        dummy = true
    }, "TLProduct", TLProduct) --[[@as TLProduct]]
    return object
end


function TLProduct:index()
    OBJECT_INDEX[self.id] = self
end


-- Returns the amount needed to satisfy this item
---@return number required_amount
function TLProduct:get_required_amount()
    if self.defined_by == "amount" then
        return self.required_amount
    else   -- defined_by == "belts" | "lanes"
        local multiplier = (self.defined_by == "belts") and 1 or 0.5
        return self.required_amount * (self.belt_proto.throughput * multiplier)
    end
end


-- Only used when switching between belts and lanes
---@param new_defined_by ProductDefinedBy
function TLProduct:change_definition(new_defined_by)
    if self.defined_by ~= "amount" and new_defined_by ~= self.defined_by then
        self.defined_by = new_defined_by

        local multiplier = (new_defined_by == "belts") and 0.5 or 2
        self.required_amount = self.required_amount * multiplier
    end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function TLProduct:paste(object)
    -- TLProduct objects are converted to SimpleItems when copied, so they can't appear here
    if object.class == "SimpleItem" or object.class == "Fuel" then
        local proto ---@type (FPItemPrototype | FPPackedPrototype)?
        proto = object.proto --[[@as FPItemPrototype | FPPackedPrototype]]
        if object.class == "Fuel" then  -- need an Item prototype here, not Fuel
            proto = prototyper.util.find("items", object:get_name_with_temperature(), proto.type) --[[@as FPItemPrototype?]]
        end

        if proto == nil or proto.simplified then return false, "incompatible" end
        ---@cast proto FPItemPrototype

        -- Avoid duplicate items, but allow pasting over the same item proto
        local existing_item = self.parent:find({proto=proto})
        if existing_item and not (self.proto.name == proto.name) then
            return false, "already_exists"
        end

        local product = init(proto)  -- defined_by = "amount"
        product.required_amount = object.amount
        self.parent:replace(self, product)

        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@class PackedProduct: PackedObject
---@field class "TLProduct"
---@field proto FPPackedPrototype
---@field defined_by ProductDefinedBy
---@field required_amount number
---@field belt_proto FPPackedPrototype?

---@param full boolean
---@return PackedProduct packed_self
function TLProduct:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        defined_by = self.defined_by,
        required_amount = self.required_amount,
        belt_proto = (self.belt_proto) and prototyper.util.simplify_prototype(self.belt_proto, nil),

        amount = (full) and self.amount or nil
    }
end

---@param packed_self PackedProduct
---@return TLProduct product
local function unpack(packed_self)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(packed_self.proto)
    unpacked_self.belt_proto = packed_self.belt_proto

    unpacked_self.defined_by = packed_self.defined_by
    unpacked_self.required_amount = packed_self.required_amount

    return unpacked_self
end


---@return boolean valid
function TLProduct:validate()
    self.valid = true

    self.proto = prototyper.util.validate_prototype_object(self.proto, "type") --[[@as FPItemPrototype | FPPackedPrototype]]
    self.valid = (not self.proto.simplified) and self.valid

    self.belt_proto = (self.belt_proto) and prototyper.util.validate_prototype_object(self.belt_proto, nil) --[[@as FPBeltPrototype | FPPackedPrototype]]
    if self.belt_proto then self.valid = (not self.belt_proto.simplified) and self.valid end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function TLProduct:repair(player)
    -- If the item is invalid, either prototype is simplified, making this unrepairable
    return false
end

return {init = init, initDummy = initDummy, unpack = unpack}

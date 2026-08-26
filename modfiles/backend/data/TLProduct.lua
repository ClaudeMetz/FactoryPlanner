local Object = require("backend.data.Object")

-- Belt-defined products are always stored in belts; lanes are only a display unit
---@alias ProductDefinedBy "amount" | "belts"

---@class TLProduct: Object, ObjectMethods
---@field class "TLProduct"
---@field parent Factory
---@field proto FPItemPrototype | FPPackedPrototype
---@field defined_by ProductDefinedBy
---@field required_amount number
---@field belt_proto (FPBeltPrototype | FPPackedPrototype)?
---@field belt_stack integer?
---@field amount number
local TLProduct = Object.methods()
TLProduct.__index = TLProduct
script.register_metatable("TLProduct", TLProduct)

---@param proto (FPItemPrototype | FPPackedPrototype)?
---@return TLProduct
local function init(proto)
    local this_proto = proto or {
        name = "",
        category = "",
        data_type = "items",
        simplified = true
    }
    local object = Object.init({
        proto = this_proto,
        defined_by = "amount",
        required_amount = 0,  -- always per second
        belt_proto = nil,
        belt_stack = nil,

        amount = 0  -- the amount satisfied by the solver
    }, "TLProduct", TLProduct)  ---@as TLProduct
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
    else   -- defined_by == "belts"
        ---@cast self.belt_proto FPBeltPrototype
        ---@cast self.belt_stack -nil
        return self.required_amount * self.belt_proto.throughput * self.belt_stack
    end
end

-- Adds to this item's requirement, converting the given amount into however it is defined
---@param added_amount number amount per second
function TLProduct:add_required_amount(added_amount)
    if self.defined_by ~= "amount" then
        ---@cast self.belt_proto FPBeltPrototype
        ---@cast self.belt_stack -nil
        added_amount = added_amount / (self.belt_proto.throughput * self.belt_stack)
    end
    self.required_amount = self.required_amount + added_amount
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function TLProduct:paste(object)
    -- TLProduct objects are converted to SimpleItems when copied, so they can't appear here
    if object.class == "SimpleItem" or object.class == "Fuel" then
        local proto  ---@type FPItemPrototype | FPPackedPrototype
        if object.class == "Fuel" then  -- need an Item prototype here, not Fuel
            proto = prototyper.util.find("items", object:get_name_with_temperature(), object.proto.type)  ---@as FPItemPrototype
        else
            proto = prototyper.util.validate_prototype_object(object.proto, "type")  ---@as FPItemPrototype | FPPackedPrototype
        end

        if proto.simplified then return false, "incompatible" end
        ---@cast proto -FPPackedPrototype

        -- The item picker doesn't offer these as products, so pasting shouldn't sneak them in
        local item_proto = proto  ---@as FPItemPrototype
        if item_proto.hidden or item_proto.ingredient_only then return false, "incompatible" end

        -- Only allow pasting fluids with set temperatures
        local temperature = object.temperature or object.proto--[[@as FPItemPrototype]].temperature or nil
        if object.proto.type == "fluid" and not temperature then
            return false, "temperature_not_set"
        end

        -- Avoid duplicate items, but allow pasting over the same item proto
        local existing_item = self.parent:find({proto=proto})
        if existing_item and not (self.proto.name == proto.name) then
            return false, "already_exists"
        end

        local product = init(proto--[[@as FPItemPrototype]])  -- defined_by = "amount"
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
---@field belt_stack integer?

---@param full boolean
---@return PackedProduct packed_self
function TLProduct:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        defined_by = self.defined_by,
        required_amount = self.required_amount,
        belt_proto = (self.belt_proto) and prototyper.util.simplify_prototype(self.belt_proto, nil) or nil,
        belt_stack = self.belt_stack,

        amount = (full) and self.amount or nil
    }
end

---@param packed_self PackedProduct
---@return TLProduct product
local function unpack(packed_self)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(packed_self.proto)

    unpacked_self.defined_by = packed_self.defined_by
    unpacked_self.required_amount = packed_self.required_amount
    unpacked_self.belt_proto = packed_self.belt_proto
    unpacked_self.belt_stack = packed_self.belt_stack

    return unpacked_self
end


---@param player LuaPlayer
---@return boolean valid
function TLProduct:validate(player)
    self.proto = prototyper.util.validate_prototype_object(self.proto, "type")  ---@as FPItemPrototype | FPPackedPrototype
    self.valid = (not self.proto.simplified)

    self.belt_proto = (self.belt_proto) and prototyper.util.validate_prototype_object(self.belt_proto, nil) or nil
    if self.belt_proto then  ---@cast self.belt_stack -nil
        self.valid = (not self.belt_proto.simplified) and self.valid

        local max_stack = prototypes.utility_constants.max_belt_stack_size
        if self.belt_stack > max_stack then
            -- The max stack size can shrink between loads, so scale the amount to keep it equivalent
            self.required_amount = self.required_amount * (self.belt_stack / max_stack)
            self.belt_stack = max_stack
        end
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function TLProduct:repair(player)
    -- If the item is invalid, either prototype is simplified, making this unrepairable
    return false
end

return {init = init, unpack = unpack}

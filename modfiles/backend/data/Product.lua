local Object = require("backend.data.Object")

---@alias ProductDefinedBy "amount" | "belts" | "lanes"

---@class Product: Object, ObjectMethods
---@field class "Product"
---@field parent Factory
---@field proto FPItemPrototype | FPPackedPrototype
---@field defined_by ProductDefinedBy
---@field required_amount number
---@field belt_proto FPBeltPrototype | FPPackedPrototype
---@field amount number
local Product = Object.methods()
Product.__index = Product
script.register_metatable("Product", Product)

---@param proto FPItemPrototype
---@return Product
local function init(proto)
    local object = Object.init({
        proto = proto,
        defined_by = "amount",
        required_amount = 0,
        belt_proto = nil,

        amount = 0  -- the amount satisfied by the solver
    }, "Product", Product)  --[[@as Product]]
    return object
end


function Product:index()
    OBJECT_INDEX[self.id] = self
end


-- Returns the amount needed to satisfy this item
---@return number required_amount
function Product:get_required_amount()
    if self.defined_by == "amount" then
        return self.required_amount
    else   -- defined_by == "belts" | "lanes"
        local multiplier = (self.defined_by == "belts") and 1 or 0.5
        return self.required_amount * (self.belt_proto.throughput * multiplier) * self.parent.timescale
    end
end


-- Only used when switching between belts and lanes
---@param new_defined_by ProductDefinedBy
function Product:update_definition(new_defined_by)
    if self.defined_by ~= "amount" and new_defined_by ~= self.defined_by then
        self.defined_by = new_defined_by

        local multiplier = (new_defined_by == "belts") and 0.5 or 2
        self.required_amount = self.required_amount * multiplier
    end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Product:paste(object)
    if object.class == "Product" or object.class == "SimpleItem" or object.class == "Fuel" then
        -- Avoid duplicate items, but allow pasting over the same item proto
        local existing_item = self.parent:find({proto=object.proto})
        if existing_item and not (self.proto.name == object.proto.name) then
            return false, "already_exists"
        end

        if object.class == "Product" then
            self.parent:replace(self, object)
        elseif object.class == "SimpleItem" or object.class == "Fuel" then
            local product = init(object.proto)
            product.required_amount = object.amount
            self.parent:replace(self, product)
        end

        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@class PackedProduct: PackedObject
---@field class "Product"
---@field proto FPPackedPrototype
---@field defined_by ProductDefinedBy
---@field required_amount number
---@field belt_proto FPPackedPrototype?

---@return PackedProduct packed_self
function Product:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        defined_by = self.defined_by,
        required_amount = self.required_amount,
        belt_proto = (self.belt_proto) and prototyper.util.simplify_prototype(self.belt_proto, nil)
    }
end

---@param packed_self PackedProduct
---@return Product Product
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto)

    unpacked_self.defined_by = packed_self.defined_by
    unpacked_self.required_amount = packed_self.required_amount
    unpacked_self.belt_proto = packed_self.belt_proto

    return unpacked_self
end


---@return boolean valid
function Product:validate()
    self.valid = true

    self.proto = prototyper.util.validate_prototype_object(self.proto, "type")
    self.valid = (not self.proto.simplified) and self.valid

    self.belt_proto = (self.belt_proto) and prototyper.util.validate_prototype_object(self.belt_proto, nil)
    if self.belt_proto then self.valid = (not self.belt_proto.simplified) and self.valid end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Product:repair(player)
    -- If the item is invalid, either prototype is simplified, making this unrepairable
    return false
end

return {init = init, unpack = unpack}

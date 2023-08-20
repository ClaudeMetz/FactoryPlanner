local Object = require("backend.data.Object")

---@class Fuel: Object, ObjectMethods
---@field class "Fuel"
---@field parent Machine
---@field proto FPFuelPrototype | FPPackedPrototype
local Fuel = Object.methods()
Fuel.__index = Fuel
script.register_metatable("Fuel", Fuel)

---@param proto FPFuelPrototype
---@param parent Machine
---@return Fuel
local function init(proto, parent)
    local object = Object.init({
        proto = proto,

        amount = 0,
        satisfied_amount = 0,

        parent = parent
    }, "Fuel", Fuel)  --[[@as Fuel]]
    return object
end


function Fuel:index()
    OBJECT_INDEX[self.id] = self
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Fuel:paste(object)
    if object.class == "Fuel" then
        local burner = self.parent.proto.burner  -- will exist if there is fuel to paste on
        for category_name, _ in pairs(burner.categories) do
            if self.proto.category == category_name then
                self.proto = object.proto
                return true, nil
            end
        end
        return false, "incompatible"
    else
        return false, "incompatible_class"
    end
end


---@class PackedFuel: PackedObject
---@field class "Fuel"
---@field proto FPFuelPrototype

---@return PackedFuel packed_self
function Fuel:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),

    }
end

---@param packed_self PackedFuel
---@return Fuel machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)

    return unpacked_self
end


---@return boolean valid
function Fuel:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

    -- Make sure the fuel categories are still compatible
    if self.valid and self.parent.valid then
        local burner = self.parent.proto.burner
        self.valid = burner and burner.categories[self.proto.category] ~= nil
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Fuel:repair(player)
    -- If the fuel-proto is still simplified, validate couldn't repair it, so it has to be removed
    return false  -- the parent machine will try to replace it with another fuel of the same category
end

return {init = init, unpack = unpack}

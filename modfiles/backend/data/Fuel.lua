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
        -- Check invididual categories so you can paste between combined_categories
        for category_name, _ in pairs(burner.categories) do
            if object.proto.category == category_name then
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
        proto = prototyper.util.simplify_prototype(self.proto, "combined_category")
    }
end

---@param packed_self PackedFuel
---@param parent Machine
---@return Fuel machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)

    return unpacked_self
end


---@return boolean valid
function Fuel:validate()
    -- Machine is simplified, doesn't have a burner anymore, or has a different category, is all bad
    local burner = (not self.parent.proto.simplified) and self.parent.proto.burner or nil
    if not burner or burner.combined_category ~= self.proto.combined_category then
        self.proto = prototyper.util.simplify_prototype(self.proto, "combined_category")
        self.valid = false
    else
        self.proto = prototyper.util.validate_prototype_object(self.proto, "combined_category")
        self.valid = (not self.proto.simplified)
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Fuel:repair(player)
    return false  -- the parent machine will try to replace it with another fuel of the same category
end

return {init = init, unpack = unpack}

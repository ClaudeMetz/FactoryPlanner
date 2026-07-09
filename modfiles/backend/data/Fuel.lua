local Object = require("backend.data.Object")

---@class Fuel: Object, ObjectMethods
---@field class "Fuel"
---@field parent Machine
---@field proto FPFuelPrototype | FPPackedPrototype
---@field temperature float?
---@field temperature_data TemperatureData
---@field amount number
---@field satisfied_amount number
local Fuel = Object.methods()
Fuel.__index = Fuel
script.register_metatable("Fuel", Fuel)

---@param parent Machine
---@param proto (FPFuelPrototype | FPPackedPrototype)?
---@return Fuel
local function init(parent, proto)
    local this_proto = proto or {
        name = "",
        category = "",
        data_type = "fuels",
        simplified = true
    }
    local object = Object.init({
        proto = this_proto,
        temperature = nil,

        temperature_data = nil,

        amount = 0,
        satisfied_amount = 0,

        parent = parent  -- could be nil
    }, "Fuel", Fuel)  ---@as Fuel

    if not this_proto.simplified then object:build_temperature_data() end

    return object
end


function Fuel:index()
    OBJECT_INDEX[self.id] = self
end


---@param proto FPFuelPrototype
---@param player LuaPlayer
function Fuel:set_proto(proto, player)
    self.proto = proto
    self:build_temperature_data()
    self:apply_temperature_default(player)
end


---@return boolean
function Fuel:is_temperature_configured()
    ---@cast self.proto FPFuelPrototype
    return (self.proto.type ~= "fluid" or self.temperature ~= nil)
end

---@return string
function Fuel:get_name_with_temperature()
    if self.proto.type ~= "fluid" or self.temperature == nil then
        return self.proto.name
    else
        return self.proto.name .. "-" .. self.temperature
    end
end

function Fuel:build_temperature_data()
    self.temperature_data = nil

    if self.proto.type == "fluid" then
        self.temperature_data = lib.temperature.generate_data(self.proto--[[@as Ingredient.fluid]])
    end
end

--- There might be no valid default to apply
---@param player LuaPlayer
function Fuel:apply_temperature_default(player)
    if self.proto.type == "fluid" then
        self.temperature = lib.temperature.determine_applicable_default(
            player, self.proto--[[@as Ingredient.fluid]], self.temperature_data.applicable_values)
    end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Fuel:paste(object)
    if object.class == "Fuel" then
        ---@cast object Fuel
        local burner = self.parent.proto.burner

        -- Sanity check. Should exist if fuel can be pasted
        if burner == nil then
            return false, "incompatible"
        end

        -- Check invididual categories so you can paste between combined_categories
        for category_name, _ in pairs(burner.categories) do
            if object.proto.category == category_name then
                self.proto = object.proto
                self.temperature = object.temperature
                self:build_temperature_data()
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
---@field proto FPPackedPrototype
---@field temperature float?
---@field amount float?

---@param full boolean
---@return PackedFuel packed_self
function Fuel:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "combined_category"),
        temperature = self.temperature,

        amount = (full) and self.amount or nil
    }
end

---@param packed_self PackedFuel
---@param parent Machine
---@return Fuel machine
local function unpack(packed_self, parent)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(parent, packed_self.proto)

    unpacked_self.temperature = packed_self.temperature  -- will be migrated through validation
    unpacked_self.amount = packed_self.amount or 0  -- only used for paste

    return unpacked_self
end


---@return boolean valid
function Fuel:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "combined_category")
    self.valid = (not self.proto.simplified)

    if self.valid then  ---@cast self.proto FPFuelPrototype
        local burner = self.parent.proto.burner
        -- Machine being simplified or not having a burner anymore invalidates the fuel
        if burner == nil or self.parent.proto.simplified then
            self.valid = false
        elseif burner.combined_category ~= self.proto.combined_category then
            if burner.categories[self.proto.category] then
                -- Fix the fuel if the combined category changed but it still has a compatible category
                self.proto = prototyper.util.find("fuels", self.proto.name, burner.combined_category)
            else
                self.valid = false
            end
        end
    end

    -- An invalid temperature shouldn't invalidate the fuel
    if self.valid then  ---@cast self.proto FPFuelPrototype
        local previous_temperature = self.temperature
        self.temperature = nil

        self:build_temperature_data()

        if self.proto.type == "fluid" and previous_temperature ~= nil then
            for _, temperature in pairs(self.temperature_data.applicable_values) do
                if temperature == previous_temperature then
                    self.temperature = previous_temperature
                    break
                end
            end
        end
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Fuel:repair(player)
    return false  -- the parent machine will try to replace it with another fuel of the same category
end

return {init = init, unpack = unpack}

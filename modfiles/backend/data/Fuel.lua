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

---@param parent Machine?
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
    if self.proto.type ~= "fluid" then return self.proto.name end
    return lib.temperature.name_with(self.proto.name, self.temperature)
end

function Fuel:build_temperature_data()
    self.temperature_data = nil
    if self.proto.type ~= "fluid" then return end
    ---@cast self.proto FPFluidFuelPrototype

    -- The machine's fluid box can narrow the temperatures further than the fuel itself allows
    local burner = (self.parent) and self.parent.proto.burner or nil
    local min_temp, exclusive_minimum = self.proto.minimum_temperature, self.proto.exclusive_minimum
    local max_temp = (burner) and burner.maximum_temperature or nil

    if burner and burner.minimum_temperature and (not min_temp or burner.minimum_temperature > min_temp) then
        -- The fuel's own minimum is the only one that can be exclusive
        min_temp, exclusive_minimum = burner.minimum_temperature, false
    end

    local bounds = {name=self.proto.name, minimum_temperature=min_temp, maximum_temperature=max_temp}
    self.temperature_data = lib.temperature.generate_data(bounds--[[@as Ingredient.fluid]], exclusive_minimum)
end

--- The energy a single unit of this fuel provides, before machine effectivity.
--- Nil when it can't be determined yet, ie. the fuel needs a temperature but has none configured.
---@return number?
function Fuel:get_fuel_value()
    ---@cast self.proto FPFluidFuelPrototype
    if self.proto.heat_capacity then  -- burned for its heat rather than its fuel value
        if self.temperature == nil then return nil end
        return (self.temperature - self.proto.default_temperature--[[@as float]]) * self.proto.heat_capacity
    end
    return self.proto.fuel_value
end

--- Rebuilds the temperature data, keeping the configured temperature only if it's still applicable.
--- Needed whenever the machine changes, since its fluid box can narrow the temperatures.
function Fuel:rebuild_temperature_data()
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

--- There might be no valid default to apply
---@param player LuaPlayer
function Fuel:apply_temperature_default(player)
    if self.proto.type == "fluid" then
        self.temperature = lib.temperature.determine_applicable_default(
            player, self.proto--[[@as Ingredient.fluid]], self.temperature_data.applicable_values)
    end
end


---@param object CopyableObject
---@param player LuaPlayer
---@return boolean success
---@return string? error
function Fuel:paste(object, player)
    local burner = self.parent.proto.burner

    -- Sanity check, should exist if fuel can be pasted
    if burner == nil then return false, "incompatible" end

    local fuel_name, temperature = nil, nil
    if object.class == "Fuel" then
        ---@cast object Fuel
        fuel_name = object.proto.name
        temperature = object.temperature
    elseif object.class == "SimpleItem" then
        ---@cast object SimpleItem
        fuel_name = object.proto.base_name or object.proto.name
        temperature = object.proto.temperature
    else
        -- Only allow pasting items and fuels
        return false, "incompatible_class"
    end

    -- Looking the fuel up by name checks compatibility across combined_categories, and picks
    -- up this machine's own prototype copy of it, so its fluid box bounds apply
    local proto = prototyper.util.find("fuels", fuel_name, burner.combined_category)  ---@as FPFuelPrototype?
    if proto == nil then return false, "incompatible" end

    self.proto = proto
    self.temperature = temperature
    -- The pasted temperature might not be applicable to this machine, which unsets it
    self:rebuild_temperature_data()
    if self.temperature == nil then self:apply_temperature_default(player) end
    return true, nil
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


---@param player LuaPlayer
---@return boolean valid
function Fuel:validate(player)
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
        self:rebuild_temperature_data()
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Fuel:repair(player)
    return false  -- the parent machine will try to replace it with another fuel of the same category
end

return {init = init, unpack = unpack}

local Object = require("backend.data.Object")

---@alias ProductionType "produce" | "consume"

---@class SurfaceCompatibility
---@field recipe boolean
---@field machine boolean
---@field overall boolean

---@class Recipe: Object, ObjectMethods
---@field class "Recipe"
---@field parent Line
---@field proto FPRecipePrototype | FPPackedPrototype
---@field production_type ProductionType
---@field priority_product (FPItemPrototype | FPPackedPrototype)?
---@field temperatures { [string]: float }
---@field temperature_data { [string]: TemperatureData }
local Recipe = Object.methods()
Recipe.__index = Recipe
script.register_metatable("Recipe", Recipe)

---@param proto FPRecipePrototype?
---@param production_type ProductionType
---@return Recipe
local function init(proto, production_type)
    local object = Object.init({
        proto = proto,
        production_type = production_type,
        priority_product = nil,
        temperatures = nil,

        temperature_data = nil
    }, "Recipe", Recipe)  --[[@as Recipe]]

    -- Initialize data related to fluid ingredients temperatures
    if object.proto and object.proto.simplified ~= true then
        object:build_temperatures_data({})
    end

    return object
end


function Recipe:index()
    OBJECT_INDEX[self.id] = self
end


-- Builds temperature data caches, and optionally migrates previous temperatures
---@param previous_temperatures { [string]: float }
function Recipe:build_temperatures_data(previous_temperatures)
    self.temperatures = {}
    self.temperature_data = {}

    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" then
            local previous = previous_temperatures[ingredient.name]
            local temperature, data = util.temperature.generate_data(ingredient, previous)

            self.temperatures[ingredient.name] = temperature
            self.temperature_data[ingredient.name] = data
        end
    end
end

---@return boolean is_fully_configured
function Recipe:temperature_fully_configured()
    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" and self.temperatures[ingredient.name] == nil then
            return false
        end
    end

    local fuel = self.parent.machine.fuel
    if fuel and fuel.proto.type == "fluid" and not fuel.temperature then return false end

    return true
end


---@class PackedRecipe: PackedObject
---@field class "Recipe"
---@field proto FPPackedPrototype
---@field production_type ProductionType
---@field priority_product FPPackedPrototype?
---@field temperatures { [string]: float }

---@return PackedRecipe packed_self
function Recipe:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
        production_type = self.production_type,
        priority_product = prototyper.util.simplify_prototype(self.priority_product, "type"),
        temperatures = self.temperatures
    }
end

---@param packed_self PackedRecipe
---@return Recipe Recipe
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto, packed_self.production_type)

    -- These will be automatically unpacked by the validation process
    unpacked_self.priority_product = packed_self.priority_product
    unpacked_self.temperatures = packed_self.temperatures

    return unpacked_self
end


---@return boolean valid
function Recipe:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, nil)
    self.valid = (not self.proto.simplified)

    if self.valid and self.priority_product then
        self.priority_product = prototyper.util.validate_prototype_object(self.priority_product, "type")
        self.valid = (not self.priority_product.simplified) and self.valid
    end

    if self.valid then self:build_temperatures_data(self.temperatures or {}) end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Recipe:repair(player)
    if self.proto.simplified then
        self.valid = false  -- this situation can't be repaired
    end

    if self.valid and self.priority_product and self.priority_product.simplified then
        self.priority_product = nil
    end

    if self.valid then self:build_temperatures_data(self.temperatures or {}) end

    return self.valid
end

return {init = init, unpack = unpack}

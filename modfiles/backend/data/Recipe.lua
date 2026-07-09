local Object = require("backend.data.Object")

---@alias RecipeProductionType "produce" | "consume"

---@class SurfaceCompatibility
---@field recipe boolean
---@field machine boolean
---@field overall boolean

---@class Recipe: Object, ObjectMethods
---@field class "Recipe"
---@field parent Line
---@field proto FPRecipePrototype | FPPackedPrototype
---@field production_type RecipeProductionType
---@field priority_product (FPItemPrototype | FPPackedPrototype)?
---@field temperatures table<string, float>
---@field temperature_data table<string, TemperatureData>
---@field effects IntegerModuleEffects?
local Recipe = Object.methods()
Recipe.__index = Recipe
script.register_metatable("Recipe", Recipe)

---@param parent Line
---@param proto (FPRecipePrototype | FPPackedPrototype)?
---@param production_type RecipeProductionType?
---@return Recipe
local function init(parent, proto, production_type)
    local this_proto = proto or {
        name = "",
        data_type = "recipes",
        simplified = true
    }
    local object = Object.init({
        proto = this_proto,
        production_type = production_type or "produce",
        priority_product = nil,
        temperatures = {},

        temperature_data = nil,
        effects = nil,

        parent = parent
    }, "Recipe", Recipe)  ---@as Recipe

    if not this_proto.simplified then
        object:build_temperatures_data()
    end

    return object
end


function Recipe:index()
    OBJECT_INDEX[self.id] = self
end


function Recipe:build_temperatures_data()
    ---@cast self.proto FPRecipePrototype
    self.temperature_data = {}

    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" then
            self.temperature_data[ingredient.name] = lib.temperature.generate_data(ingredient)
        end
    end
end

--- There might be no valid default to apply
---@param player LuaPlayer
function Recipe:apply_temperature_defaults(player)
    ---@cast self.proto FPRecipePrototype
    for _, ingredient in pairs(self.proto.ingredients) do
        if ingredient.type == "fluid" then
            local applicable_values = self.temperature_data[ingredient.name].applicable_values
            self.temperatures[ingredient.name] = lib.temperature.determine_applicable_default(
                player, ingredient, applicable_values)
        end
    end
end


---@param ingredient Ingredient | FPItemPrototype
---@return boolean
function Recipe:is_temperature_configured(ingredient)
    return (ingredient.type ~= "fluid" or self.temperatures[ingredient.name] ~= nil)
end

---@param ingredient Ingredient | FPItemPrototype | SimpleItem
---@return string
function Recipe:get_name_with_temperature(ingredient)
    if ingredient.type ~= "fluid" then
        return ingredient.name  ---@as string
    else
        local temperature = self.temperatures[ingredient.name]
        if temperature ~= nil then
            return ingredient.name .. "-" .. temperature
        else
            return ingredient.name  ---@as string
        end
    end
end


---@param ingredient Ingredient | FPItemPrototype
---@return float?
function Recipe:get_temperature(ingredient)
    if ingredient.type == "fluid" then
        return self.temperatures[ingredient.name]
    end
    return nil
end


---@param ingredient Ingredient | FPItemPrototype
---@param temperature float?
---@return boolean success
function Recipe:set_temperature(ingredient, temperature)
    if temperature == nil then return false end
    if ingredient.type == "fluid" and self.temperatures[ingredient.name] then
        -- Check that the temperature to be set is a valid temperature
        for _, value in pairs(self.temperature_data[ingredient.name].applicable_values) do
            if temperature == value then
                self.temperatures[ingredient.name] = temperature
                return true
            end
        end
    end

    return false
end


--- Called when the solver runs because it's the most convenient spot for it
---@param force LuaForce
---@param factory Factory
function Recipe:update_effects(force, factory)
    local machine_proto = self.parent.machine.proto

    local name = nil
    local drill = (machine_proto.prototype_category == "mining_drill")
    if drill and machine_proto.uses_force_mining_productivity_bonus then name = "custom-mining"
    elseif self.proto.productivity_recipe ~= nil then name = self.proto.productivity_recipe
    else return end  -- no recipe effects for custom recipes

    self.effects = {productivity = factory:get_productivity_bonus(force, name--[[@cast -nil]])}
    self.parent.machine:summarize_effects()  -- update machine to update its tooltip
end


---@class PackedRecipe: PackedObject
---@field class "Recipe"
---@field proto FPPackedPrototype
---@field production_type RecipeProductionType
---@field priority_product FPPackedPrototype?
---@field temperatures table<string, float>

---@param full boolean
---@return PackedRecipe packed_self
function Recipe:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
        production_type = self.production_type,
        priority_product = (self.priority_product) and
            prototyper.util.simplify_prototype(self.priority_product, "type") or nil,
        temperatures = self.temperatures
    }
end

---@param packed_self PackedRecipe
---@param parent Line
---@return Recipe Recipe
local function unpack(packed_self, parent)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(parent, packed_self.proto, packed_self.production_type)
    unpacked_self.priority_product = packed_self.priority_product

    -- Will be automatically unpacked by the validation process
    unpacked_self.temperatures = packed_self.temperatures

    return unpacked_self
end


---@return boolean valid
function Recipe:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, nil)  ---@as FPRecipePrototype | FPPackedPrototype
    self.valid = (not self.proto.simplified)

    if self.valid and self.priority_product then
    end

    self.priority_product = (self.priority_product) and
        prototyper.util.validate_prototype_object(self.priority_product, "type") or nil
    if self.priority_product then self.valid = (not self.priority_product.simplified) and self.valid end

    -- An invalid temperature shouldn't invalidate the recipe
    if self.valid then  ---@cast self.proto FPRecipePrototype
        local previous_temperatures = self.temperatures
        self.temperatures = {}

        self:build_temperatures_data()

        for _, ingredient in pairs(self.proto.ingredients) do
            if ingredient.type == "fluid" then
                local applicable_values = self.temperature_data[ingredient.name].applicable_values
                local previous_temperature = previous_temperatures[ingredient.name]

                if #applicable_values == 1 then
                    self.temperatures[ingredient.name] = applicable_values[1]
                elseif previous_temperature ~= nil then
                    for _, temperature in pairs(applicable_values) do
                        if temperature == previous_temperature then
                            self.temperatures[ingredient.name] = previous_temperature
                            break
                        end
                    end
                end
            end
        end
    end

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

    return self.valid
end

return {init = init, unpack = unpack}

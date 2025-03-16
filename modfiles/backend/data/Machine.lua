local Object = require("backend.data.Object")
local Fuel = require("backend.data.Fuel")
local ModuleSet = require("backend.data.ModuleSet")

---@class Machine: Object, ObjectMethods
---@field class "Machine"
---@field parent Line
---@field proto FPMachinePrototype | FPPackedPrototype
---@field quality_proto FPQualityPrototype
---@field limit number?
---@field force_limit boolean
---@field fuel Fuel?
---@field module_set ModuleSet
---@field amount number
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
---@field recipe_effects ModuleEffects?
local Machine = Object.methods()
Machine.__index = Machine
script.register_metatable("Machine", Machine)

---@param proto FPMachinePrototype
---@param parent Line
---@return Machine
local function init(proto, parent)
    local object = Object.init({
        proto = proto,
        quality_proto = defaults.get_fallback("qualities").proto,
        limit = nil,
        force_limit = true,  -- ignored if limit is not set
        fuel = nil,  -- needs to be set by calling Machine.normalize_fuel afterwards
        module_set = nil,

        amount = 0,
        total_effects = nil,
        effects_tooltip = "",
        recipe_effects = nil,

        parent = parent
    }, "Machine", Machine)  --[[@as Machine]]
    object.module_set = ModuleSet.init(object)
    return object
end


function Machine:index()
    OBJECT_INDEX[self.id] = self
    if self.fuel then self.fuel:index() end
    self.module_set:index()
end


---@return {name: string, quality: string}
function Machine:elem_value()
    return {name=self.proto.name, quality=self.quality_proto.name}
end


---@param player LuaPlayer
function Machine:normalize_fuel(player)
    if self.proto.energy_type ~= "burner" then self.fuel = nil; return end
    -- no need to continue if this machine doesn't have a burner

    local burner = self.proto.burner
    -- Check if fuel has a valid category for this machine, replace otherwise
    if self.fuel and not burner.categories[self.fuel.proto.category] then self.fuel = nil end

    if self.fuel == nil then  -- add a fuel for this machine if it doesn't have one here
        local default_fuel_proto = defaults.get(player, "fuels", burner.combined_category).proto
        self.fuel = Fuel.init(default_fuel_proto, self)
    else  -- make sure the fuel is of the right combined category
        if burner.combined_category ~= self.fuel.proto.category then
            self.fuel.proto = prototyper.util.find("fuels", self.fuel.proto.name, burner.combined_category)
        end
    end
end


function Machine:summarize_effects()
    local module_effects = self.module_set:get_effects()
    local machine_effects = self.proto.effect_receiver.base_effect

    self.total_effects = util.effects.merge({module_effects, machine_effects, self.recipe_effects})
    self.effects_tooltip = util.effects.format(module_effects,
        {machine_effects=machine_effects, recipe_effects=self.recipe_effects})

    self.parent:summarize_effects()
end

---@return boolean uses_effects
function Machine:uses_effects()
    if self.proto.effect_receiver == nil then return false end
    return self.proto.effect_receiver.uses_module_effects
end

--- Called when the solver runs because it's the most convenient spot for it
---@param force LuaForce
---@param factory Factory
function Machine:update_recipe_effects(force, factory)
    local recipe_proto = self.parent.recipe_proto

    local recipe_name = nil
    if self.proto.prototype_category == "mining_drill" then recipe_name = "custom-mining"
    elseif recipe_proto.productivity_recipe then recipe_name = recipe_proto.productivity_recipe
    elseif not recipe_proto.custom then recipe_name = recipe_proto.name
    else return end  -- no recipe effects for custom recipes

    local recipe_bonus = factory:get_productivity_bonus(force, recipe_name)
    self.recipe_effects = {productivity=recipe_bonus}
    self:summarize_effects()
end


function Machine:compile_fuel_filter()
    local compatible_fuels = {}

    local fuel_category = prototyper.util.find("fuels", nil, self.proto.burner.combined_category)
    for _, fuel_proto in pairs(fuel_category.members) do
        table.insert(compatible_fuels, fuel_proto.name)
    end

    return {{filter="name", name=compatible_fuels}}
end

---@param player LuaPlayer
function Machine:reset(player)
    self.parent:change_machine_to_default(player)
    self:normalize_fuel(player)

    self.limit = nil
    self.force_limit = true

    self.module_set:clear()
    local machine_default = defaults.get(player, "machines", self.proto.category)
    if machine_default.modules then self.module_set:ingest_default(machine_default.modules) end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Machine:paste(object, player)
    if object.class == "Machine" then
        local corresponding_proto = prototyper.util.find("machines", object.proto.name, self.proto.category)
        if corresponding_proto and self.parent:is_machine_compatible(object.proto) then
            self.parent:change_machine_to_proto(player, corresponding_proto)
            self.quality_proto = object.quality_proto

            self.limit = object.limit
            self.force_limit = object.force_limit

            if object.fuel then
                self.fuel = object.fuel
                self.fuel.parent = self
            end

            self.module_set = object.module_set
            self.module_set.parent = self
            -- Need to verify compatibility because it depends on the recipe too
            self.module_set:normalize({compatibility=true, effects=true})

            return true, nil
        else
            return false, "incompatible"
        end
    elseif object.class == "Module" then
       return self.module_set:paste(object)
    else
        return false, "incompatible_class"
    end
end


---@class PackedMachine: PackedObject
---@field class "Machine"
---@field proto FPMachinePrototype
---@field quality_proto FPQualityPrototype
---@field limit number?
---@field force_limit boolean
---@field fuel PackedFuel?
---@field module_set PackedModuleSet

---@return PackedMachine packed_self
function Machine:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        quality_proto = prototyper.util.simplify_prototype(self.quality_proto, nil),
        limit = self.limit,
        force_limit = self.force_limit,
        fuel = self.fuel and self.fuel:pack(),
        module_set = self.module_set:pack()
    }
end

---@param packed_self PackedMachine
---@param parent Line
---@return Machine machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)
    unpacked_self.quality_proto = packed_self.quality_proto
    unpacked_self.limit = packed_self.limit
    unpacked_self.force_limit = packed_self.force_limit
    unpacked_self.fuel = packed_self.fuel and Fuel.unpack(packed_self.fuel, unpacked_self)
    unpacked_self.module_set = ModuleSet.unpack(packed_self.module_set, unpacked_self)

    return unpacked_self
end

---@return Machine clone
function Machine:clone()
    local clone = unpack(self:pack(), self.parent)

    -- Copy these over so we don't need to run the solver
    clone.amount = self.amount
    clone.recipe_effects = self.recipe_effects
    if self.fuel then
        clone.fuel.amount = self.fuel.amount
        clone.fuel.satisfied_amount = self.fuel.satisfied_amount
    end

    clone:validate()
    return clone
end


---@return boolean valid
function Machine:validate()
    local recipe_category = self.parent.recipe_proto.category
    if recipe_category ~= self.proto.category then
        local corresponding_proto = prototyper.util.find("machines", self.proto.name, recipe_category)
        if corresponding_proto then  -- check if the machine just moved categories
            self.proto = corresponding_proto  -- this is okay in this specific context
        else  -- otherwise, this machine is invalid
            self.proto = prototyper.util.simplify_prototype(self.proto, "category")
            self.valid = false
        end
    else
        self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
        self.valid = (not self.proto.simplified)
    end

    self.quality_proto = prototyper.util.validate_prototype_object(self.quality_proto, nil)
    self.valid = (not self.quality_proto.simplified) and self.valid

    -- Only need to check compatibility when the below is valid, else it'll be replaced anyways
    if not self.proto.simplified and not self.parent.recipe_proto.simplified then
        self.valid = self.parent:is_machine_compatible(self.proto) and self.valid
    end

    if self.valid then  -- only makes sense if the machine is valid
        if self.proto.burner and not self.fuel then
            -- If this machine changed to require fuel, add this dummy
        local dummy = {name = "", category = self.proto.burner.combined_category,
                data_type = "fuels", simplified = true}
            self.fuel = Fuel.init(dummy, self)
        end
        if self.fuel then self.valid = self.fuel:validate() and self.valid end
    end

    self.valid = self.module_set:validate() and self.valid

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Machine:repair(player)
    self.valid = true

    -- Simplified or incompatible machine can potentially be replaced with a different one
    if self.proto.simplified or not self.parent:is_machine_compatible(self.proto) then
        -- Changing to the default machine also fixes the category not matching the recipe
        if not self.parent:change_machine_to_default(player) then
            self.valid = false  -- this situation can't be repaired
        end
    end

    if self.valid and self.quality_proto.simplified then
        self.quality_proto = defaults.get_fallback("qualities").proto
    end

    if self.valid and self.fuel and not self.fuel.valid then
        if not self.fuel:repair(player) then
            self.fuel = nil  -- replace fuel with its default
            self:normalize_fuel(player)
        end
    end

    if self.valid then
        self.module_set:repair(player)  -- always becomes valid
    end

    return self.valid
end

return {init = init, unpack = unpack}

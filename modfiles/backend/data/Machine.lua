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
        quality_proto = prototyper.defaults.get_fallback("qualities"),
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

    -- If this machine has fuel already, don't replace it
    if self.fuel == nil then
        -- Use the first category of this machine's burner as the default one
        local fuel_category_name, _ = next(burner.categories, nil)

        local default_fuel_proto = prototyper.defaults.get(player, "fuels", fuel_category_name)
        self.fuel = Fuel.init(default_fuel_proto, self)
    end
end


function Machine:summarize_effects()
    local module_effects = self.module_set:get_effects()
    local machine_effects = self.proto.effect_receiver.base_effect

    self.effects_tooltip = util.gui.format_module_effects(module_effects,
        {machine_effects=machine_effects, recipe_effects=self.recipe_effects})
    self.total_effects = util.merge_effects({module_effects, machine_effects, self.recipe_effects})

    self.parent:summarize_effects()
end

---@return boolean uses_effects
function Machine:uses_effects()
    return self.proto.effect_receiver.uses_module_effects
end

--- Called when the solver runs because it's the most convenient spot for it
---@param force LuaForce
function Machine:update_recipe_effects(force)
    local mining_bonus = force.mining_drill_productivity_bonus
    if mining_bonus > 0 and self.proto.quality_category == "mining-drill" then
        self.recipe_effects = {productivity=mining_bonus}
        self:summarize_effects()
    end

    if self.parent.recipe_proto.custom then return end
    local recipe_bonus = force.recipes[self.parent.recipe_proto.name].productivity_bonus
    if recipe_bonus > 0 then
        self.recipe_effects = {productivity=recipe_bonus}
        self:summarize_effects()
    end
end


function Machine:compile_fuel_filter()
    local compatible_fuels = {}

    for category_name, _ in pairs(self.proto.burner.categories) do
        local category = prototyper.util.find("fuels", nil, category_name)
        if category ~= nil then
            for _, fuel_proto in pairs(category.members) do
                table.insert(compatible_fuels, fuel_proto.name)
            end
        end
    end

    return {{filter="name", name=compatible_fuels}}
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Machine:paste(object)
    if object.class == "Machine" then
        local found_machine = prototyper.util.find("machines", object.proto.name, self.proto.category)

        if found_machine and self.parent:is_machine_applicable(object.proto) then
            object.parent = self.parent
            self.parent.machine = object

            self.parent.surface_compatibility = nil  -- reset since the machine changed
            object.module_set:normalize({compatibility=true, effects=true})
            object.parent:summarize_effects()
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

    clone:validate()
    return clone
end


---@return boolean valid
function Machine:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

    self.quality_proto = prototyper.util.validate_prototype_object(self.quality_proto, nil)
    self.valid = (not self.quality_proto.simplified) and self.valid

    if self.valid and self.parent.valid then
        self.valid = self.parent:is_machine_applicable(self.proto)
    end

    -- If the machine changed to not use a burner, remove its fuel
    if not self.proto.burner then self.fuel = nil end
    if self.fuel and self.valid then self.valid = self.fuel:validate() end

    self.valid = self.module_set:validate() and self.valid

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Machine:repair(player)
    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- A final possible fix is to replace this machine with the default for its category
    if self.proto.simplified and not self.parent:change_machine_to_default(player) then
        return false  -- if this happens, the whole line can not be salvaged
    end
    self.valid = true  -- if it gets to this, change_machine was successful and the machine is valid
    -- It just might need to cleanup some fuel, modules and/or quality

    if self.quality_proto.simplified then self.quality_proto = prototyper.defaults.get_fallback("qualities") end

    if self.fuel and not self.fuel.valid and not self.fuel:repair(player) then
        -- If fuel is unrepairable, replace it with a default value
        self.fuel = nil
        self:normalize_fuel(player)
    end

    self.module_set:repair(player)

    return self.valid
end

return {init = init, unpack = unpack}

local Object = require("backend.data.Object")
local Fuel = require("backend.data.Fuel")
local ModuleSet = require("backend.data.ModuleSet")

---@class Machine: Object, ObjectMethods
---@field class "Machine"
---@field parent Line
---@field proto FPMachinePrototype | FPPackedPrototype
---@field limit number?
---@field force_limit boolean
---@field fuel Fuel?
---@field module_set ModuleSet
---@field amount number
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
local Machine = Object.methods()
Machine.__index = Machine
script.register_metatable("Machine", Machine)

---@param proto FPMachinePrototype
---@param parent Line
---@return Machine
local function init(proto, parent)
    local object = Object.init({
        proto = proto,
        limit = nil,
        force_limit = true,  -- ignored if limit is not set
        fuel = nil,  -- needs to be set by calling Machine.find_fuel afterwards
        module_set = nil,

        amount = 0,
        total_effects = nil,
        effects_tooltip = "",

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
        local fuel_category_id = PROTOTYPE_MAPS.fuels[fuel_category_name].id

        local default_fuel_proto = prototyper.defaults.get(player, "fuels", fuel_category_id)
        self.fuel = Fuel.init(default_fuel_proto, self)
    end
end


function Machine:summarize_effects()
    self.total_effects = self.module_set.total_effects
    self.effects_tooltip = util.gui.format_module_effects(self.total_effects, false)

    self.parent:summarize_effects()
end

---@param module_proto FPModulePrototype
---@return boolean compatible
function Machine:check_module_compatibility(module_proto)
    if self.proto.module_limit == 0 then return false end

    local allowed_effects = self.proto.allowed_effects
    if allowed_effects == nil then
        return false
    else
        for effect_name, _ in pairs(module_proto.effects) do
            if allowed_effects[effect_name] == false then
                return false
            end
        end
    end

    return true
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Machine:paste(object)
    if object.class == "Machine" then
        local found_machine = prototyper.util.find_prototype("machines", object.proto.name, self.proto.category)

        if found_machine and self.parent:is_machine_applicable(object.proto) then
            object.parent = self.parent
            self.parent.machine = object

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
---@field limit number?
---@field force_limit boolean
---@field fuel PackedFuel?
---@field module_set PackedModuleSet

---@return PackedMachine packed_self
function Machine:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        limit = self.limit,
        force_limit = self.force_limit,
        fuel = self.fuel and self.fuel:pack(),
        module_set = self.module_set:pack()
    }
end

---@param packed_self PackedMachine
---@return Machine machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)
    unpacked_self.limit = packed_self.limit
    unpacked_self.force_limit = packed_self.force_limit
    unpacked_self.fuel = packed_self.fuel and Fuel.unpack(packed_self.fuel, unpacked_self)
    unpacked_self.module_set = ModuleSet.unpack(packed_self.module_set, unpacked_self)

    return unpacked_self
end

---@return Machine clone
function Machine:clone()
    local clone = unpack(self:pack(), self.parent)
    clone:validate()
    return clone
end


---@return boolean valid
function Machine:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

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
    -- It just might need to cleanup some fuel and/or modules

    if self.fuel and not self.fuel.valid and not self.fuel:repair(player) then
        -- If fuel is unrepairable, replace it with a default value
        self.fuel = nil
        self:normalize_fuel(player)
    end

    self.module_set:repair()

    return self.valid
end

return {init = init, unpack = unpack}

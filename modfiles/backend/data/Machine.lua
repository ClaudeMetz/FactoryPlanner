local Object = require("backend.data.Object")

---@class Machine: Object, ObjectMethods
---@field class "Machine"
---@field parent Line
---@field proto FPMachinePrototype | FPPackedPrototype
---@field limit number?
---@field force_limit boolean
---@field amount number
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
local Machine = Object.methods()
Machine.__index = Machine
script.register_metatable("Machine", Machine)

---@return Machine
local function init(proto)
    local object = Object.init({
        proto = proto,
        limit = nil,
        force_limit = true,

        amount = 0,
        total_effects = nil,
        effects_tooltip = ""
    }, "Machine", Machine)  --[[@as Machine]]
    return object
end


function Machine:index()
    OBJECT_INDEX[self.id] = self
end

function Machine:cleanup()
    OBJECT_INDEX[self.id] = nil
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

            --ModuleSet.normalize(object.module_set, {compatibility=true, effects=true})
            --Line.summarize_effects(object.parent)
            return true, nil
        else
            return false, "incompatible"
        end
    elseif object.class == "Module" then
       --return ModuleSet.paste(self.module_set, object)
    else
        return false, "incompatible_class"
    end
end


---@class PackedMachine: PackedObject
---@field class "Machine"
---@field proto FPMachinePrototype
---@field limit number?
---@field force_limit boolean

---@return PackedMachine packed_self
function Machine:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        limit = self.limit,
        force_limit = self.force_limit
    }
end

---@param packed_self PackedMachine
---@return Machine machine
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto)
    unpacked_self.limit = packed_self.limit
    unpacked_self.force_limit = packed_self.force_limit


    return unpacked_self
end

---@return Machine clone
function Machine:clone()
    local clone = unpack(self:pack())
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


    return self.valid
end

return {init = init, unpack = unpack}

local Object = require("backend.data.Object")

---@class Module: Object, ObjectMethods
---@field class "Module"
---@field parent ModuleSet
---@field proto FPModulePrototype | FPPackedPrototype
---@field amount integer
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
local Module = Object.methods()
Module.__index = Module
script.register_metatable("Module", Module)

---@param proto FPModulePrototype
---@param amount integer
---@return Module
local function init(proto, amount)
    local object = Object.init({
        proto = proto,
        amount = amount,

        total_effects = nil,
        effects_tooltip = ""
    }, "Module", Module)  --[[@as Module]]
    if not proto.simplified then object:summarize_effects() end
    return object
end


function Module:index()
    OBJECT_INDEX[self.id] = self
end

function Module:cleanup()
    OBJECT_INDEX[self.id] = nil
end


---@param new_amount integer
function Module:set_amount(new_amount)
    self.amount = new_amount
    self.parent:count_modules()
    self:summarize_effects()
end

function Module:summarize_effects()
    local effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
    for name, effect in pairs(self.proto.effects) do
        effects[name] = effect.bonus * self.amount
    end
    self.total_effects = effects
    self.effects_tooltip = util.gui.format_module_effects(effects, false)
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Module:paste(object)
    if object.class == "Module" then
        ---@cast object Module
        if self.parent:check_compatibility(object.proto) then
            if self.parent:find({proto=object.proto}) and object.proto.name ~= self.proto.name then
                return false, "already_exists"
            else
                object.amount = math.min(object.amount, self.amount + self.parent.empty_slots)
                object:summarize_effects()

                self.parent:replace(self, object)
                self.parent:summarize_effects()
                return true, nil
            end
        else
            return false, "incompatible"
        end
    else
        return false, "incompatible_class"
    end
end


---@class PackedModule: PackedObject
---@field class "Module"
---@field proto FPModulePrototype
---@field amount integer

---@return PackedModule packed_self
function Module:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        amount = self.amount
    }
end

---@param packed_self PackedModule
---@return Module module
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto, packed_self.amount)

    return unpacked_self
end


---@return boolean valid
function Module:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

    -- Check whether the module is still compatible with its machine or beacon
    if self.valid and self.parent and self.parent.valid then
        self.valid = self.parent.parent:check_module_compatibility(self.proto)
    end

    if self.valid then self:summarize_effects() end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Module:repair(player)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end


return {init = init, unpack = unpack}

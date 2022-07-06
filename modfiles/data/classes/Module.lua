-- 'Class' representing an module
Module = {}

-- Initialised by passing a prototype from the all_moduless global table
function Module.init(proto, amount, parent)
    local module = {
        proto = proto,
        amount = amount,
        total_effects = nil,
        effects_tooltip = "",
        valid = true,
        class = "Module",
        parent = parent
    }
    Module.summarize_effects(module)

    return module
end


function Module.set_amount(self, new_amount)
    self.amount = new_amount
    ModuleSet.normalize(self.parent, {})  -- adjust metadata
    Module.summarize_effects(self)
end

function Module.summarize_effects(self)
    local effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
    for name, effect in pairs(self.proto.effects) do
        effects[name] = effect.bonus * self.amount
    end
    self.total_effects = effects
    self.effects_tooltip = data_util.format_module_effects(effects, false)
end


function Module.paste(self, object)
    if object.class == "Module" then
        if ModuleSet.check_compatibility(self.parent, object.proto) then
            if ModuleSet.get_by_name(self.parent, object.proto.name) and object.proto.name ~= self.proto.name then
                return false, "already_exists"
            else
                object.amount = math.min(object.amount, self.parent.module_limit)
                ModuleSet.replace(self.parent, self, object)
                ModuleSet.summarize_effects(self.parent)
                return true, nil
            end
        else
            return false, "incompatible"
        end
    else
        return false, "incompatible_class"
    end
end


function Module.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        amount = self.amount,
        class = self.class
    }
end

function Module.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto
function Module.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "modules", "category")

    -- Check whether the module is still compatible with its machine or beacon
    if self.valid and self.parent.valid then
        self.valid = _G[self.parent.parent.class].check_module_compatibility(self.parent.parent, self.proto)
    end

    if self.valid then Module.summarize_effects(self) end

    return self.valid
end

-- Needs repair:
function Module.repair(_, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end

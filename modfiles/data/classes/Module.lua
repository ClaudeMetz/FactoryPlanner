-- 'Class' representing an module
Module = {}

-- Initialised by passing a prototype from the all_moduless global table
function Module.init_by_proto(proto, amount)
    return {
        proto = proto,
        amount = amount,
        effects_tooltip = "",
        valid = true,
        class = "Module"
    }
end

-- lookup exists for internal purposes
function Module.clone(self, lookup)
    lookup = lookup or {}
    local new = {}
    lookup[self] = new
    for k, v in pairs(self) do
        new[k] = lookup[v] or v
    end
    return new
end


function Module.change_amount(self, new_amount)
    local amount_difference = new_amount - self.amount
    self.amount = new_amount

    self.parent.module_count = self.parent.module_count + amount_difference
    Line.summarize_effects(self.parent.parent, true, false)
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

    -- Check whether the module is still compatible with it's machine or beacon
    if self.valid and self.parent.valid then
        _G[self.parent.class].check_module_compatibility(self.parent, self.proto)
    end

    return self.valid
end

-- Needs repair:
function Module.repair(_, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end

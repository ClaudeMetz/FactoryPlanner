-- 'Class' representing an module
Module = {}

-- Initialised by passing a prototype from the all_moduless global table
function Module.init_by_proto(proto, amount)
    return {
        proto = proto,
        amount = amount,
        valid = true,
        class = "Module"
    }
end

-- Initialised by passing a category- and module prototype-id
function Module.init_by_ids(category_id, id, amount)
    local proto = global.all_modules.categories[category_id].modules[id]
    Module.init_by_proto(proto, amount)
end


function Module.change_amount(self, new_amount)
    local amount_difference = new_amount - self.amount
    self.amount = new_amount

    self.parent.module_count = self.parent.module_count + amount_difference
    Line.summarize_effects(self.parent.parent, true, false)
end


-- Needs validation: proto
function Module.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "modules", "category")

    -- Check whether the module is still compatible with it's machine
    if self.valid and self.parent.valid then
        local parent, characteristics = self.parent, nil

        -- Different validation strategies depending on the use case of this module
        if parent.class == "Beacon" then
            characteristics = Line.get_beacon_module_characteristics(parent.parent, parent.proto, self.proto)
        else  -- parent.class == "Machine"
            characteristics = Machine.get_module_characteristics(parent, self.proto, false)
        end

        self.valid = characteristics.compatible
    end

    return self.valid
end

-- Needs repair: proto
function Module.repair(_, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    return false
end
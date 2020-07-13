-- This is essentially just a wrapper-'class' for a machine prototype to add some data to it
Machine = {}

-- Initialised by passing a prototype from the all_machines global table
function Machine.init_by_proto(proto)
    return {
        proto = proto,
        count = 0,
        limit = nil,  -- will be set by the user
        hard_limit = false,
        valid = true,
        class = "Machine"
    }
end


-- Needs validation: proto
function Machine.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "machines", "category")

    local parent_line = self.parent
    if self.valid and parent_line.valid and parent_line.recipe.valid then
        self.valid = Line.is_machine_applicable(parent_line, self.proto)
    end

    return self.valid
end

-- Needs repair: proto
function Machine.repair(self, player)
    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- A final possible fix is to replace this machine with the default for its category
    self.valid = Line.change_machine(self.parent, player, nil, nil)
    return self.valid
end
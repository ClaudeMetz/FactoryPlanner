-- This is essentially just a wrapper-'class' for a machine prototype to add some data to it
Machine = {}

-- Initialised by passing a prototype from the all_machines global table
function Machine.init_by_proto(proto)
    return {
        proto = proto,
        count = 0,
        limit = nil,  -- will be set by the user
        hard_limit = false,
        Module = Collection.init(),
        valid = true,
        class = "Machine"
    }
end


function Machine.add(self, object)
    object.parent = self
    local dataset = Collection.add(self[object.class], object)

    Line.normalize_modules(self.parent, true, false)
    return dataset
end

function Machine.remove(self, dataset)
    local removed_gui_position = Collection.remove(self[dataset.class], dataset)

    Line.normalize_modules(self.parent, true, false)
    return removed_gui_position
end

function Machine.replace(self, dataset, object)
    local new_dataset = Collection.replace(self[dataset.class], dataset, object)

    Line.normalize_modules(self.parent, true, false)
    return new_dataset
end

function Machine.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Machine.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end


-- Needs validation: proto, Module
function Machine.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "machines", "category")

    local parent_line = self.parent
    if self.valid and parent_line.valid and parent_line.recipe.valid then
        self.valid = Line.is_machine_applicable(parent_line, self.proto)
    end



    return self.valid
end

-- Needs repair: proto, Module
function Machine.repair(self, player)
    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- A final possible fix is to replace this machine with the default for its category
    self.valid = Line.change_machine(self.parent, player, nil, nil)



    return self.valid
end
-- This is essentially just a wrapper-'class' for a machine prototype to add some data to it
Machine = {}

-- Initialised by passing a prototype from the all_machines global table
function Machine.init_by_proto(proto)
    local category = global.all_machines.categories[global.all_machines.map[proto.category]]
    return {
        proto = proto,
        category = category,
        count = 0,
        sprite = ("entity/" .. proto.name),
        valid = true,
        class = "Machine"
    }
end

-- Initialised by passing a machine prototype id
function Machine.init_by_ids(category_id, id)
    local proto = global.all_machines.categories[category_id].machines[id]
    Machine.init_by_proto(proto)
end


-- Update the validity of this machine
function Machine.update_validity(self)
    local new_category_id = new.all_machines.map[self.category.name]
    if new_category_id ~= nil then
        self.category = new.all_machines.categories[new_category_id]

        new_machine_id = self.category.map[self.proto.name]
        if new_machine_id ~= nil then
            self.proto = self.category.machines[new_machine_id]
            self.valid = true
        else
            self.proto = self.proto.name
            self.valid = false
        end
    else
        self.category = self.category.name
        self.proto = self.proto.name
        self.valid = false
    end
    
    return self.valid
end

-- Tries to repair this machine, deletes it otherwise (by returning false)
-- If this is called, the machine is invalid and has a string saved to proto (and maybe to category)
function Machine.attempt_repair(self, player)
    -- First, try and repair the category if necessary
    if type(self.category) == "string" then
        local current_category_id = global.all_machines.map[self.category.name]
        if current_category_id ~= nil then
            self.category = global.all_machines.categories[current_category_id]
        else  -- delete immediately if no matching type can be found
            self.category = nil
            return false
        end
    end
    
    -- At this point, category is always valid (and proto is always a string)
    local current_machine_id = self.category.map[self.proto]
    if current_machine_id ~= nil then
        self.proto = self.category.machines[current_machine_id]
        self.sprite = ("entity/" .. proto.name)
        self.valid = true
    else
        self.valid = false
    end

    return self.valid
end
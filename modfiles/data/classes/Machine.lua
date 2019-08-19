-- This is essentially just a wrapper-'class' for a machine prototype to add some data to it
Machine = {}

-- Initialised by passing a prototype from the all_machines global table
function Machine.init_by_proto(proto)
    local category = global.all_machines.categories[global.all_machines.map[proto.category]]
    return {
        proto = proto,
        category = category,
        count = 0,
        valid = true,
        class = "Machine"
    }
end


-- Update the validity of this machine
function Machine.update_validity(self, recipe)
    local category_name = (type(self.category) == "string") and self.category or self.category.name
    local new_category_id = new.all_machines.map[category_name]

    if new_category_id ~= nil then
        self.category = new.all_machines.categories[new_category_id]
        
        local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
        local new_machine_id = self.category.map[proto_name]

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

    -- If the machine is valid, it might still not be applicable
    if self.valid and (not recipe.valid or not data_util.machine.is_applicable(self.proto, recipe)) then
        self.valid = false
    end
    
    return self.valid
end

-- Tries to repair this machine, deletes it otherwise (by returning false)
-- If this is called, the machine is invalid and has a string saved to proto (and maybe to category)
function Machine.attempt_repair(self, player)
    -- If the category is nil, this machine is not repairable
    if self.category == nil then
        return false
    -- First, try and repair the category if necessary
    elseif type(self.category) == "string" then
        local current_category_id = global.all_machines.map[self.category]
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
        self.valid = true
    else
        self.valid = false
    end

    return self.valid
end
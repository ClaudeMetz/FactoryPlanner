-- This is essentially just a wrapper-'class' for a fuel prototype to add some data to it
Fuel = {}

-- Initialised by passing a prototype from the all_fuels global table
function Fuel.init_by_proto(proto)
    return {
        proto = proto,
        amount = 0,  -- produced amount
        valid = true,
        class = "Fuel"
    }
end

-- Initialised by passing a basic item table {name, type, amount}
function Fuel.init_by_item(item, amount)
    local proto = item_fuel_map[item.type][item.name]
    return Fuel.init_by_proto(proto, amount)
end


-- Update the validity of this fuel
function Fuel.update_validity(self, line)
    if self.category == nil or self.proto == nil then return false end
    local category_name = (type(self.category) == "string") and self.category or self.category.name
    local new_category_id = new.all_fuels.map[category_name]

    if new_category_id ~= nil then
        self.category = new.all_fuels.categories[new_category_id]

        if self.proto == nil then self.valid = false; return self.valid end
        local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
        local new_fuel_id = self.category.map[proto_name]

        if new_fuel_id ~= nil then
            self.proto = self.category.fuels[new_fuel_id]
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

    -- Check fuel category compatibility
    if self.valid and line.valid and line.machine and line.machine.valid and line.machine.proto then
        local burner = line.machine.proto.burner
        if not burner or burner.categories[self.proto.category] == nil then
            self.valid = false
        end
    end

    return self.valid
end

-- Tries to repair this fuel, deletes it otherwise (by returning false)
-- If this is called, the fuel is invalid and has a string saved to proto (and maybe to type)
function Fuel.attempt_repair(self, _, line)
    -- If the category is nil, this fuel is not repairable
    if self.category == nil then
        return false
    -- First, try and repair the category if necessary
    elseif type(self.category) == "string" then
        local current_category_id = global.all_fuels.map[self.category]
        if current_category_id ~= nil then
            self.category = global.all_fuels.categories[current_category_id]
        else  -- delete immediately if no matching type can be found
            self.category = nil
            return false
        end
    end

    -- At this point, category is always valid (and proto is always a string)
    local current_fuel_id = self.category.map[self.proto]
    if current_fuel_id ~= nil then
        self.proto = self.category.fuels[current_fuel_id]
        self.valid = true
    else
        self.valid = false
    end

    -- Fix fuel category compatibility
    local burner = line.machine.proto.burner
    if self.valid and (not burner or burner.categories[self.proto.category] == nil) then
        self.valid = false
    end

    return self.valid
end
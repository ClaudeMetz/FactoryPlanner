-- This is essentially just a wrapper-'class' for a fuel prototype to add some data to it
Fuel = {}

-- Initialised by passing a prototype from the all_fuels global table
function Fuel.init_by_proto(proto, amount)
    return {
        proto = proto,
        amount = amount or 0,  -- produced amount
        valid = true,
        class = "Fuel"
    }
end

-- Initialised by passing a basic item table {name, type, amount}
function Fuel.init_by_item(item, amount)
    local proto = global.all_fuels.fuels[global.all_fuels.map[item.name]]
    return Fuel.init_by_proto(proto, amount)
end


-- Update the validity of this fuel
function Fuel.update_validity(self)
    local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
    local new_fuel_id = new.all_fuels.map[proto_name]
    
    if new_fuel_id ~= nil then
        self.proto = new.all_fuels.fuels[new_fuel_id]
        self.valid = true
    else
        self.proto = self.proto.name
        self.valid = false
    end

    -- Check fuel category compatibility
    local burner = self.parent.machine.proto.burner
    if self.valid and not (burner and burner.categories[self.fuel_category]) then
        self.valid = false
    end

    return self.valid
end

-- Tries to repair this fuel, deletes it otherwise (by returning false)
-- If this is called, the fuel is invalid and has a string saved to proto (and maybe to type)
function Fuel.attempt_repair(self, player)
    local current_fuel_id = global.all_fuels.map[self.proto]
    if current_fuel_id ~= nil then
        self.proto = global.all_fuels.fuels[current_fuel_id]
        self.valid = true
    end

    -- Fix fuel category compatibility
    local burner = parent.machine.proto.burner
    if self.valid and not (burner and burner.categories[self.fuel_category]) then
        self.valid = false
    end

    return self.valid
end
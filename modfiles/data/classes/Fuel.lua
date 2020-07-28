-- This is essentially just a wrapper-'class' for a fuel prototype to add some data to it
Fuel = {}

-- Initialised by passing a prototype from the all_fuels global table
function Fuel.init_by_proto(proto)
    return {
        proto = proto,
        amount = 0,  -- produced amount
        satisfied_amount = 0,  -- used with ingredient satisfaction
        valid = true,
        class = "Fuel"
    }
end


function Fuel.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        class = self.class
    }
end

function Fuel.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto
function Fuel.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "fuels", "category")

    -- Make sure the fuel categories are still compatible
    if self.valid and self.parent.valid then
        local burner = self.parent.proto.burner
        self.valid = not (burner and burner.categories[self.proto.category] == nil)
    end

    return self.valid
end

-- Needs repair: proto
function Fuel.repair(self, player)
    self.parent.fuel = nil  -- invalid fuels need to be removed

    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- To repair it, replace it with the default for its machine's category
    if self.proto.simplified then
        Machine.find_fuel(self.parent, player)
    end
    -- no return necessary
end
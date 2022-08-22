-- This is essentially just a wrapper-'class' for a fuel prototype to add some data to it
Fuel = {}

function Fuel.init(proto)
    return {
        proto = proto,
        amount = 0,  -- produced amount
        satisfied_amount = 0,  -- used with ingredient satisfaction
        valid = true,
        parent = nil,
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
        self.valid = burner and burner.categories[self.proto.category] ~= nil
    end

    return self.valid
end

-- Needs repair:
function Fuel.repair(_, _)
    -- If the fuel-proto is still simplified, validate couldn't repair it, so it has to be removed
    return false  -- the parent machine will try to replace it with another fuel of the same category
end

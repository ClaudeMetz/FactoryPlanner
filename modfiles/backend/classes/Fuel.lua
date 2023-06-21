---@class FPFuel
---@field proto FPFuelPrototype
---@field amount number
---@field satisfied_amount number
---@field valid boolean
---@field parent FPLine
---@field class "Fuel"

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


function Fuel.paste(self, object)
    if object.class == "Fuel" then
        local burner = self.parent.proto.burner  -- will exist if there is fuel to paste on
        for category_name, _ in pairs(burner.categories) do
            if self.proto.category == category_name then
                self.proto = object.proto
                return true, nil
            end
        end
        return false, "incompatible"
    else
        return false, "incompatible_class"
    end
end


function Fuel.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto, self.proto.category),
        amount = self.amount,  -- conserve for cloning
        class = self.class
    }
end

function Fuel.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto
function Fuel.validate(self)
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

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

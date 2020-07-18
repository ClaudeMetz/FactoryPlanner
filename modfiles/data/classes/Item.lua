-- 'Class' representing an item in the general sense
Item = {}

-- Initialised by passing a prototype from the all_items global table
-- This is set up as a top-level item if a required_amount is given
function Item.init_by_proto(proto, class, amount, required_amount)
    -- Special case for non-product top level items
    if required_amount == 0 then required_amount = {defined_by="amount", amount=0} end

    return {
        proto = proto,
        amount = amount or 0,  -- produced amount
        required_amount = required_amount,  -- is a table
        satisfied_amount = 0,  -- used with ingredient satisfaction
        top_level = (required_amount ~= nil),
        valid = true,
        class = class
    }
end


-- Initialised by passing a basic item table {name, type, amount}
-- This is set up as a top-level item if a required_amount is given
function Item.init_by_item(item, class, amount, required_amount)
    local type = global.all_items.types[global.all_items.map[item.type]]
    local proto = type.items[type.map[item.name]]
    return Item.init_by_proto(proto, class, amount, required_amount)
end


-- Returns the converted numeric required_amount for this (top level) item
function Item.required_amount(self)
    local req_amount = self.required_amount
    if req_amount.defined_by == "amount" then
        return req_amount.amount
    else  -- defined_by == "belts"/"lanes"
        -- If this is defined by lanes, only half of the throughput of a full belt needs to be considered
        local multiplier = (req_amount.defined_by == "belts") and 1 or 0.5
        local timescale = self.parent.timescale
        return req_amount.amount * (req_amount.belt_proto.throughput * multiplier) * timescale
    end
end


-- This will only be called on top level items, so they can be treated as such
function Item.pack(self)
    local belt_proto = (self.required_amount.defined_by ~= "amount") and
      prototyper.util.simplify_prototype(self.required_amount.belt_proto) or nil

    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        required_amount = {
            defined_by = self.required_amount.defined_by,
            amount = self.required_amount.amount,
            belt_proto = belt_proto
        },
        top_level = true,
        class = self.class
    }
end

-- This will only be called on top level items, so they can be treated as such
function Item.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto, required_amount
-- This will only be called on top level items, so they can be treated as such
function Item.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "items", "type")

    -- Validate the belt_proto if the item proto is still valid, ie not simplified
    local req_amount = self.required_amount
    if req_amount.defined_by ~= "amount" then
        local belt_throughput = req_amount.belt_proto.throughput
        self.valid = prototyper.util.validate_prototype_object(req_amount, "belt_proto", "belts", nil) and self.valid

        -- If the proto has to be simplified, conserve the throughput, so repair can convert it to an amount-spec
        if req_amount.belt_proto.simplified then req_amount.belt_proto.throughput = belt_throughput end
    end

    return self.valid
end

-- Needs repair: required_amount
-- This will only be called on top level items, so they can be treated as such
function Item.repair(self, _)
    -- If the item-proto is still simplified, validate couldn't repair it, so it has to be removed
    if self.proto.simplified then return false end

    -- If the item is fine, the belt_proto has to be simplified. Thus, we will repair this item
    -- by converting it to be defined by amount, so the whole can be preserved
    self.required_amount = {
        defined_by = "amount",
        amount = Item.required_amount(self)
    }
    self.valid = true

    return self.valid
end
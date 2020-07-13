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


-- Needs validation: proto, required_amount.belt_proto
function Item.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "items", "type")

    -- TODO: should probably generalize this along the lines of a normal prototype
    -- Might also want to keep the prototype unsimplified so I can do a smarter repair
    -- where I switch it to an amount-based item

    local req_amount = self.required_amount
    -- Validate the belt_proto if the item proto is still valid, ie not simplified
    if self.valid and req_amount.defined_by ~= "amount" then
        local belt_proto = req_amount.belt_proto
        local new_proto = prototyper.util.get_new_prototype_by_name("belts", belt_proto.name, nil)
        if new_proto then
            req_amount.belt_proto = new_proto
        else
            req_amount.belt_proto = prototyper.util.simplify_prototype(belt_proto)
            self.valid = false
        end
    end

    return self.valid
end

-- Needs repair: proto, required_amount.belt_proto
function Item.repair(self, _)
    -- If the prototype is still simplified, it couldn't be fixed by validate, so it has to be removed
    if self.proto.simplified then return false
    elseif self.required_amount.belt_proto and self.required_amount.belt_proto.simplified then return false
    else self.valid = true; return true end
end
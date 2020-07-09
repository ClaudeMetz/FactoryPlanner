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


-- Needs to validate: proto, required_amount.belt_proto
function Item.validate(self)
    self.valid = prototyper.validate.prototype_object(self, "items", "type")

    -- TODO: should probably generalize this along the lines of a normal prototype
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



--[[
-- Tries to repair this item, deletes it otherwise (by returning false)
-- If this is called, the item is invalid and has a string saved to proto (and maybe to type)
function Item.attempt_repair(self, _)
    -- First, try and repair the type if necessary
    if type(self.type) == "string" then
        local current_type_id = global.all_items.map[self.type]
        if current_type_id ~= nil then
            self.type = global.all_items.types[current_type_id]
        else  -- delete immediately if no matching type can be found
            return false
        end
    end

    -- At this point, type is always valid (and proto is always a string)
    local current_item_id = self.type.map[self.proto]
    if current_item_id ~= nil then
        self.proto = self.type.items[current_item_id]
        self.valid = true
    else
        self.valid = false
    end

    -- Try and repair the belt_proto related to the required_amounts
    -- (Doesn't seem to work, but w/e, the invalidity check works)
    if self.valid and self.top_level then
        local belt_proto = self.required_amount.belt_proto
        if belt_proto and type(belt_proto) == "string" then
            -- valid stays true
            self.required_amount.belt_proto = new.all_belts.belts[new.all_belts.map[belt_proto] ]
        else
            self.valid = false
        end
    end

    return self.valid
end ]]
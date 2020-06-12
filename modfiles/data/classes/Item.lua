-- 'Class' representing an item in the general sense
Item = {}

-- Initialised by passing a prototype from the all_items global table
-- This is set up as a top-level item if a required_amount is given
function Item.init_by_proto(proto, class, amount, required_amount)
    local type = global.all_items.types[global.all_items.map[proto.type]]

    -- Special case for non-product top level items
    if required_amount == 0 then required_amount = {defined_by="amount", amount=0} end

    return {
        proto = proto,
        type = type,
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


-- Update the validity of this item
function Item.update_validity(self)
    local type_name = (type(self.type) == "string") and self.type or self.type.name
    local new_type_id = new.all_items.map[type_name]

    if new_type_id ~= nil then
        self.type = new.all_items.types[new_type_id]

        if self.proto == nil then self.valid = false; return self.valid end
        local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
        local new_item_id = self.type.map[proto_name]

        if new_item_id ~= nil then
            self.proto = self.type.items[new_item_id]
            self.valid = true
        else
            self.proto = self.proto.name
            self.valid = false
        end
    else
        self.type = self.type.name
        self.proto = self.proto.name
        self.valid = false
    end

    -- Check the belt_proto related to the required_amounts of top level items
    if self.valid and self.top_level then
        local belt_proto = self.required_amount.belt_proto
        if belt_proto ~= nil then
            if new.all_belts.map[belt_proto.name] == nil then
                self.required_amount.belt_proto = belt_proto.name
                self.valid = false
            end
        end
    end

    return self.valid
end

-- Tries to repair this item, deletes it otherwise (by returning false)
-- If this is called, the item is invalid and has a string saved to proto (and maybe to type)
function Item.attempt_repair(self, player)
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
            self.required_amount.belt_proto = new.all_belts.belts[new.all_belts.map[belt_proto]]
        else
            self.valid = false
        end
    end

    return self.valid
end
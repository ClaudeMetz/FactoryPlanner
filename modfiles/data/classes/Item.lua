-- 'Class' representing an item in the general sense
Item = {}
Product, Byproduct, Ingredient = Item, Item, Item  -- allows _G[class] to work for all items

-- Initialised by passing a prototype from the all_items global table
-- This is set up as a top-level item if a required_amount is given
function Item.init(proto, class, amount, required_amount)
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


function Item.paste(self, object)
    if object.class == "Product" or object.class == "Byproduct" or object.class == "Ingredient" then
        local existing_item = Subfactory.get_by_name(self.parent, self.class, object.proto.name)
        -- Avoid duplicate items, but allow pasting over the same item proto
        if existing_item and existing_item.proto.name == object.proto.name
         and not (self.proto.name == object.proto.name) then
            return false, "already_exists"
        end

        -- Convert object into the appropriate top-level form if necessary
        if not (object.top_level and object.class == self.class) then
            object.required_amount = {defined_by = "amount", amount = object.amount}
            object.class = self.class
        end

        -- Detect when this is called on a fake item and add instead of replacing
        if not self.amount then Subfactory.add(self.parent, object)
        else Subfactory.replace(self.parent, self, object) end
        return true, nil
    else
        return false, "incompatible_class"
    end
end


function Item.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        amount = self.amount,  -- conserve for cloning non-product items
        required_amount = (self.top_level) and {
            defined_by = self.required_amount.defined_by,
            amount = self.required_amount.amount,
            belt_proto = (self.required_amount.defined_by ~= "amount") and
              prototyper.util.simplify_prototype(self.required_amount.belt_proto)
        } or nil,
        top_level = self.top_level,
        class = self.class
    }
end

function Item.unpack(packed_self)
    return packed_self
end


-- Needs validation: proto, required_amount
function Item.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "items", "type")

    -- Validate the belt_proto if the item proto is still valid, ie not simplified
    local req_amount = self.required_amount
    if req_amount and req_amount.defined_by ~= "amount" then
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

    -- If the item is fine, the belt_proto has to be the things that is invalid. Thus, we will repair
    -- this item by converting it to be defined by amount, so it can be preserved in some form
    self.required_amount = {
        defined_by = "amount",
        amount = Item.required_amount(self)
    }
    self.valid = true

    return self.valid
end

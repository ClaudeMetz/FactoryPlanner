local Object = require("backend.data.Object")

---@alias ItemCategory "product" | "ingredient"

---@alias ItemDefinitionType "amount" | "belts" | "machines"
---@alias ItemDefinition AmountItemDefinition | BeltItemDefinition | MachineItemDefinition

---@class AmountItemDefinition
---@field type "amount"
---@field amount number

---@class BeltItemDefinition
---@field type "belts"
---@field belt_count number Full belts, regardless of the display preference
---@field belt_proto FPBeltPrototype | FPPackedPrototype
---@field belt_stack integer

---@class MachineItemDefinition
---@field type "machines"
---@field machine_count number

---@class FactoryItem: Object, ObjectMethods
---@field class "FactoryItem"
---@field parent Factory
---@field proto FPItemPrototype | FPPackedPrototype
---@field quality_proto (FPQualityPrototype | FPPackedPrototype)?
---@field category ItemCategory
---@field definition ItemDefinition
---@field active boolean
---@field amount number
local FactoryItem = Object.methods()
FactoryItem.__index = FactoryItem
script.register_metatable("FactoryItem", FactoryItem)

---@param category ItemCategory
---@param proto (FPItemPrototype | FPPackedPrototype)?
---@param quality_proto (FPQualityPrototype | FPPackedPrototype)?
---@return FactoryItem
local function init(category, proto, quality_proto)
    local this_proto = proto or {
        name = "",
        category = "",
        data_type = "items",
        simplified = true
    }
    local object = Object.init({
        proto = this_proto,
        quality_proto = quality_proto,
        category = category,
        definition = {type="amount", amount=0},
        active = true,

        amount = 0  -- the amount satisfied by the solver
    }, "FactoryItem", FactoryItem)  ---@as FactoryItem
    return object
end


function FactoryItem:index()
    OBJECT_INDEX[self.id] = self
end


-- Machine definitions have no item amount target
---@return number? amount
function FactoryItem:get_defined_amount()
    local definition = self.definition
    if definition.type == "amount" then
        ---@cast definition AmountItemDefinition
        return definition.amount
    elseif definition.type == "belts" then
        ---@cast definition BeltItemDefinition
        local belt = definition.belt_proto  ---@as FPBeltPrototype
        return definition.belt_count * belt.throughput * definition.belt_stack
    end
end

-- Adds an item amount, converting it to the definition's unit; machine counts stay unchanged
---@param added_amount number
function FactoryItem:add_defined_amount(added_amount)
    local definition = self.definition
    if definition.type == "amount" then
        ---@cast definition AmountItemDefinition
        definition.amount = definition.amount + added_amount
    elseif definition.type == "belts" then
        ---@cast definition BeltItemDefinition
        local belt = definition.belt_proto  ---@as FPBeltPrototype
        definition.belt_count = definition.belt_count
            + added_amount / (belt.throughput * definition.belt_stack)
    end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function FactoryItem:paste(object)
    if object.class == "FactoryItem" or object.class == "SimpleItem" or object.class == "Fuel" then
        local proto
        if object.class == "Fuel" then  -- need an Item prototype here, not Fuel
            proto = prototyper.util.find("items", object:get_name_with_temperature(), object.proto.type)
        else
            proto = object.proto
        end
        ---@cast proto FPItemPrototype

        -- Avoid duplicate items, but allow pasting over the same item proto
        local existing_item = self.parent:find({proto=proto})
        if existing_item and existing_item ~= self then
            return false, "already_exists_as_" .. existing_item.category
        end

        if not lib.availability.can_define_factory_item(proto, self.category) then return false, "incompatible" end

        -- Only allow pasting fluids with set temperatures
        local temperature = (object.class == "Fuel") and object.temperature or proto.temperature
        if object.proto.type == "fluid" and not temperature then return false, "temperature_not_set" end

        local item
        if object.class == "FactoryItem" then
            item = object
        else
            local source = object  ---@as SimpleItem | Fuel
            item = init(self.category, proto, source.quality_proto)  -- definition.type = "amount"
            item.definition = {type="amount", amount=source.amount}
        end
        item.category = self.category
        self.parent:replace(self, item)

        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@class PackedFactoryItem: PackedObject
---@field class "FactoryItem"
---@field proto FPPackedPrototype
---@field quality_proto FPPackedPrototype?
---@field category ItemCategory
---@field definition ItemDefinition
---@field active boolean

---@param full boolean
---@return PackedFactoryItem packed_self
function FactoryItem:pack(full)
    local definition = lib.flib.shallow_copy(self.definition)
    if definition.type == "belts" then
        ---@cast definition BeltItemDefinition
        definition.belt_proto = prototyper.util.simplify_prototype(definition.belt_proto, nil)
    end
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "type"),
        quality_proto = (self.quality_proto) and prototyper.util.simplify_prototype(self.quality_proto) or nil,
        category = self.category,
        definition = definition,
        active = self.active,

        amount = (full) and self.amount or nil
    }
end

---@param packed_self PackedFactoryItem
---@return FactoryItem item
local function unpack(packed_self)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(packed_self.category,
        packed_self.proto, packed_self.quality_proto)

    unpacked_self.definition = lib.flib.deep_copy(packed_self.definition)
    unpacked_self.active = packed_self.active

    return unpacked_self
end


---@param player LuaPlayer
---@return boolean valid
function FactoryItem:validate(player)
    self.proto = prototyper.util.validate_prototype_object(self.proto, "type")  ---@as FPItemPrototype | FPPackedPrototype
    self.valid = (not self.proto.simplified)

    self.quality_proto = self.quality_proto and prototyper.util.validate_prototype_object(self.quality_proto)
    self.quality_proto = (self.quality_proto and not self.quality_proto.simplified) and self.quality_proto or nil

    local definition = self.definition
    if definition.type == "belts" then
        ---@cast definition BeltItemDefinition
        local belt = definition.belt_proto  ---@as FPBeltPrototype | FPPackedPrototype
        definition.belt_proto = prototyper.util.validate_prototype_object(belt, nil)  ---@as FPBeltPrototype | FPPackedPrototype
        self.valid = (not definition.belt_proto.simplified) and self.valid

        local max_stack = prototypes.utility_constants.max_belt_stack_size
        if definition.belt_stack > max_stack then
            -- Preserve throughput when the maximum belt stack size shrinks
            definition.belt_count = definition.belt_count
                * (definition.belt_stack / max_stack)
            definition.belt_stack = max_stack
        end
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function FactoryItem:repair(player)
    -- If the item is invalid, either prototype is simplified, making this unrepairable
    return false
end

return {init = init, unpack = unpack}

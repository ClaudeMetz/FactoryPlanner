local Object = require("backend.data.Object")
local Machine = require("backend.data.Machine")
local Beacon = require("backend.data.Beacon")

---@alias ProductionType "input" | "output"

---@class Line: Object, ObjectMethods
---@field class "Line"
---@field parent Floor
---@field recipe_proto FPRecipePrototype | FPPackedPrototype
---@field production_type ProductionType
---@field done boolean
---@field active boolean
---@field percentage number
---@field machine Machine
---@field beacon Beacon?
---@field priority_product (FPItemPrototype | FPPackedPrototype)?
---@field comment string
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
---@field first_product SimpleItem?
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field power number
---@field pollution number
---@field production_ratio number?
---@field uncapped_production_ratio number?
local Line = Object.methods()
Line.__index = Line
script.register_metatable("Line", Line)

---@param recipe_proto FPRecipePrototype
---@param production_type ProductionType
---@return Line
local function init(recipe_proto, production_type)
    local object = Object.init({
        recipe_proto = recipe_proto,
        production_type = production_type,
        done = false,
        active = false,
        percentage = 100,
        machine = nil,
        beacon = nil,
        priority_product = nil,
        comment = "",

        total_effects = nil,
        effects_tooltip = "",
        first_product = nil,
        first_byproduct = nil,
        first_ingredient = nil,
        power = 0,
        pollution = 0,
        production_ratio = 0,
        uncapped_production_ratio = 0
    }, "Line", Line)  --[[@as Line]]
    return object
end


function Line:index()
    OBJECT_INDEX[self.id] = self
    self.machine:index()
end

function Line:cleanup()
    OBJECT_INDEX[self.id] = nil
    self.machine:cleanup()
end


---@param item_category SimpleItemCategory
---@return fun(): SimpleItem?
function Line:item_iterator(item_category)
    return self:_iterator(nil, self["first_" .. item_category])
end

---@param item_category SimpleItemCategory
---@param filter ObjectFilter
function Line:find_item(item_category, filter)
    return self:_find(filter, self["first_" .. item_category])
end


-- Returns whether the given machine can be used for this line/recipe
---@param machine_proto FPMachinePrototype
---@return boolean applicable
function Line:is_machine_applicable(machine_proto)
    local type_counts = self.recipe_proto.type_counts
    local valid_ingredient_count = (machine_proto.ingredient_limit >= type_counts.ingredients.items)
    local valid_input_channels = (machine_proto.fluid_channels.input >= type_counts.ingredients.fluids)
    local valid_output_channels = (machine_proto.fluid_channels.output >= type_counts.products.fluids)

    return (valid_ingredient_count and valid_input_channels and valid_output_channels)
end

-- Sets this line's machine to be the given prototype
---@param player LuaPlayer
---@param proto FPMachinePrototype
function Line:change_machine_to_proto(player, proto)
    if not self.machine then
        self.machine = Machine.init(proto, self)
        --ModuleSet.summarize_effects(self.machine.module_set)
    else
        self.machine.proto = proto

        --ModuleSet.normalize(self.machine.module_set, {compatibility=true, trim=true, effects=true})
        if self.machine.proto.allowed_effects == nil then self:set_beacon(nil) end
    end

    -- Make sure the machine's fuel still applies
    self.machine:normalize_fuel(player)
end

-- Up- or downgrades this line's machine, if possible
-- Returns false if no compatible machine can be found, true otherwise
---@param player LuaPlayer
---@param action "upgrade" | "downgrade"
---@param current_proto FPMachinePrototype?
---@return boolean success
function Line:change_machine_by_action(player, action, current_proto)
    local current_machine_proto = current_proto or self.machine.proto
    local machines_category = PROTOTYPE_MAPS.machines[current_machine_proto.category]
    local category_machines = global.prototypes.machines[machines_category.id].members

    if action == "upgrade" then
        local max_machine_id = #category_machines

        while current_machine_proto.id < max_machine_id do
            current_machine_proto = category_machines[current_machine_proto.id + 1]

            if self:is_machine_applicable(current_machine_proto) then
                self:change_machine_to_proto(player, current_machine_proto)
                return true
            end
        end
    else  -- action == "downgrade"
        while current_machine_proto.id > 1 do
            current_machine_proto = category_machines[current_machine_proto.id - 1]

            if self:is_machine_applicable(current_machine_proto) then
                self:change_machine_to_proto(player, current_machine_proto)
                return true
            end
        end
    end

    return false  -- if the above loop didn't return, no machine could be found
end

-- Changes this line's machine to its default, if possible
-- Returns false if no compatible machine can be found, true otherwise
---@param player LuaPlayer
---@return boolean success
function Line:change_machine_to_default(player)
    local machine_category_id = PROTOTYPE_MAPS.machines[self.recipe_proto.category].id
    -- All categories are guaranteed to have at least one machine, so this is never nil
    local default_machine_proto = prototyper.defaults.get(player, "machines", machine_category_id)
    ---@cast default_machine_proto FPMachinePrototype

    -- If the default is applicable, just set it straight away
    if self:is_machine_applicable(default_machine_proto) then
        self:change_machine_to_proto(player, default_machine_proto)
        return true
    -- Otherwise, go up, then down the category to find an alternative
    elseif self:change_machine_by_action(player, "upgrade", default_machine_proto) then
        return true
    elseif self:change_machine_by_action(player, "downgrade", default_machine_proto) then
        return true
    else  -- no machine in the whole category is applicable
        return false
    end
end


---@param beacon Beacon?
function Line:set_beacon(beacon)
    self.beacon = beacon  -- can be nil

    if beacon ~= nil then
        self.beacon.parent = self
        --beacon.module_set:normalize({sort=true, effects=true})
    else
        --self:summarize_effects()
    end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Line:paste(object)
    if object.class == "Line" or object.class == "Floor" then
        ---@cast object LineObject
        if not self.parent:check_product_compatibility(object) then
            return false, "recipe_irrelevant"  -- found no use for the recipe's products
        end

        self.parent:replace(self, object)
        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@class PackedLine: PackedObject
---@field class "Line"
---@field recipe_proto FPPackedPrototype
---@field production_type ProductionType
---@field done boolean
---@field active boolean
---@field percentage number
---@field machine PackedMachine
---@field beacon PackedBeacon?
---@field priority_product FPPackedPrototype?
---@field comment string

---@return PackedLine packed_self
function Line:pack()
    return {
        class = self.class,
        recipe_proto = prototyper.util.simplify_prototype(self.recipe_proto, nil),
        production_type = self.production_type,
        done = self.done,
        active = self.active,
        percentage = self.percentage,
        machine = self.machine:pack(),
        beacon = self.beacon and self.beacon:pack(),
        priority_product = prototyper.util.simplify_prototype(self.priority_product, "type"),
        comment = self.comment
    }
end

---@param packed_self PackedLine
---@return Line line
local function unpack(packed_self)
    local unpacked_self = init(packed_self.recipe_proto, packed_self.production_type)
    unpacked_self.done = packed_self.done
    unpacked_self.active = packed_self.active
    unpacked_self.percentage = packed_self.percentage
    unpacked_self.machine = Machine.unpack(packed_self.machine, unpacked_self)  --[[@as Machine]]
    unpacked_self.beacon = packed_self.beacon and Beacon.unpack(packed_self.beacon, unpacked_self)  --[[@as Beacon]]
    -- The prototype will be automatically unpacked by the validation process
    unpacked_self.priority_product = packed_self.priority_product
    unpacked_self.comment = packed_self.comment

    return unpacked_self
end


---@return boolean valid
function Line:validate()
    self.recipe_proto = prototyper.util.validate_prototype_object(self.recipe_proto, nil)
    self.valid = (not self.recipe_proto.simplified)

    self.valid = self.machine:validate() and self.valid

    if self.beacon then self.valid = self.beacon:validate() and self.valid end

    if self.priority_product ~= nil then
        self.priority_product = prototyper.util.validate_prototype_object(self.priority_product, "type")
        self.valid = (not self.priority_product.simplified) and self.valid
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Line:repair(player)
    -- An invalid recipe_proto is unrepairable and means this line should be removed
    if self.recipe_proto.simplified then return false end

    if self.valid and not self.machine.valid then
        self.valid = self.machine:repair(player)
    end

    if self.valid and self.beacon and not self.beacon.valid then
        -- Repairing a beacon always either fixes or gets it removed, so no influence on validity
        if not self.beacon:repair(player) then self.beacon = nil end
    end

    if self.valid and self.priority_product and self.priority_product.simplified then
        self.priority_product = nil
    end

    return self.valid
end

return {init = init, unpack = unpack}

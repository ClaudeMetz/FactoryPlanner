local Object = require("backend.data.Object")
local Machine = require("backend.data.Machine")
local Beacon = require("backend.data.Beacon")
local Module = require("backend.data.Module")
local SimpleItems = require("backend.data.SimpleItems")

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
---@field products SimpleItems
---@field byproducts SimpleItems
---@field ingredients SimpleItems
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
        active = true,
        percentage = 100,
        machine = nil,
        beacon = nil,
        priority_product = nil,
        comment = "",

        total_effects = nil,
        effects_tooltip = "",
        products = SimpleItems.init(),
        byproducts = SimpleItems.init(),
        ingredients = SimpleItems.init(),
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
    self.beacon:index()
end

function Line:cleanup()
    OBJECT_INDEX[self.id] = nil
    self.machine:cleanup()
    self.beacon:cleanup()
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
        self.machine.module_set:summarize_effects()
    else
        self.machine.proto = proto

        self.machine.module_set:normalize({compatibility=true, trim=true, effects=true})
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
        beacon.module_set:normalize({sort=true, effects=true})
    else
        self:summarize_effects()
    end
end

function Line:summarize_effects()
    local beacon_effects = (self.beacon) and self.beacon.total_effects or nil

    local effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
    for _, effect_table in pairs({self.machine.total_effects, beacon_effects}) do
        for name, effect in pairs(effect_table) do
            if name == "base_prod" or name == "mining_prod" then
                effects["productivity"] = effects["productivity"] + effect
            else
                effects[name] = effects[name] + effect
            end
        end
    end
    self.total_effects = effects
    self.effects_tooltip = util.gui.format_module_effects(effects, true)
end


---@param player LuaPlayer
function Line:apply_mb_defaults(player)
    self.machine.module_set:clear()
    self:set_beacon(nil)

    local mb_defaults = util.globals.preferences(player).mb_defaults
    local machine_module, secondary_module = mb_defaults.machine, mb_defaults.machine_secondary
    local module_set, module_limit = self.machine.module_set, self.machine.proto.module_limit
    local message = nil

    if machine_module and self.machine:check_module_compatibility(machine_module) then
        local module = Module.init(machine_module, module_limit)
        module_set:insert(module)

    elseif secondary_module and self.machine:check_module_compatibility(secondary_module) then
        local module = Module.init(secondary_module, module_limit)
        module_set:insert(module)

    elseif machine_module then  -- only show an error if any module default is actually set
        message = {text={"fp.warning_module_not_compatible", {"fp.pl_module", 1}}, category="warning"}
    end
    self.machine.module_set:summarize_effects()

    -- Add default beacon modules, if desired by the user
    local beacon_module_proto, beacon_count = mb_defaults.beacon, mb_defaults.beacon_count
    if BEACON_OVERLOAD_ACTIVE then beacon_count = 1 end
    local beacon_proto = prototyper.defaults.get(player, "beacons")  --[[@as FPBeaconPrototype]]

    if beacon_module_proto ~= nil and beacon_count ~= nil then
        local blank_beacon = Beacon.init(beacon_proto, self)
        blank_beacon.amount = beacon_count

        if blank_beacon:check_module_compatibility(beacon_module_proto) then
            local module = Module.init(beacon_module_proto, beacon_proto.module_limit)
            blank_beacon.module_set:insert(module)
            self:set_beacon(blank_beacon)  -- summarizes effects on its own

        elseif message == nil then  -- don't overwrite previous message, if it exists
            message = {text={"fp.warning_module_not_compatible", {"fp.pl_beacon", 1}}, category="warning"}
        end
    end

    return message
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

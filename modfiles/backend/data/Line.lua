local Object = require("backend.data.Object")
local Machine = require("backend.data.Machine")
local Beacon = require("backend.data.Beacon")
local SimpleItems = require("backend.data.SimpleItems")

---@alias ProductionType "produce" | "consume"

---@class SurfaceCompatibility
---@field recipe boolean
---@field machine boolean
---@field overall boolean

---@class Line: Object, ObjectMethods
---@field class "Line"
---@field parent Floor
---@field next LineObject?
---@field previous LineObject?
---@field recipe_proto FPRecipePrototype | FPPackedPrototype
---@field production_type ProductionType
---@field done boolean
---@field active boolean
---@field percentage number
---@field machine Machine
---@field beacon Beacon?
---@field priority_product (FPItemPrototype | FPPackedPrototype)?
---@field comment string
---@field surface_compatibility SurfaceCompatibility?
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
---@field products SimpleItems
---@field byproducts SimpleItems
---@field ingredients SimpleItems
---@field power number
---@field emissions number
---@field production_ratio number?
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
        products = SimpleItems.init(),
        byproducts = SimpleItems.init(),
        ingredients = SimpleItems.init(),
        priority_product = nil,
        comment = "",

        surface_compatibility = nil,  -- determined on demand
        total_effects = nil,
        effects_tooltip = "",
        power = 0,
        emissions = 0,
        production_ratio = 0
    }, "Line", Line)  --[[@as Line]]
    return object
end


function Line:index()
    OBJECT_INDEX[self.id] = self
    self.machine:index()
    if self.beacon then self.beacon:index() end
    self.products:index()
    self.byproducts:index()
    self.ingredients:index()
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
        self.machine:summarize_effects()
    else
        self.machine.proto = proto

        self.machine.module_set:normalize({compatibility=true, trim=true, effects=true})
        if not self.machine:uses_effects() then self:set_beacon(nil) end
        self.surface_compatibility = nil  -- reset it since the machine changed
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
    local category_id = current_machine_proto.category_id

    local function try_machine(new_machine_id)
        current_machine_proto = prototyper.util.find("machines", new_machine_id, category_id) --[[@as FPMachinePrototype]]

        if self:is_machine_applicable(current_machine_proto) then
            self:change_machine_to_proto(player, current_machine_proto)
            return true
        end
        return false
    end

    if action == "upgrade" then
        local max_machine_id = #prototyper.util.find("machines", nil, category_id).members
        while current_machine_proto.id < max_machine_id do
            if try_machine(current_machine_proto.id + 1) then return true end
        end
    else  -- action == "downgrade"
        while current_machine_proto.id > 1 do
            if try_machine(current_machine_proto.id - 1) then return true end
        end
    end

    return false  -- if the above loop didn't return, no machine could be found
end

-- Changes this line's machine to its default, if possible
-- Returns false if no compatible machine can be found, true otherwise
---@param player LuaPlayer
---@return boolean success
function Line:change_machine_to_default(player)
    -- All categories are guaranteed to have at least one machine, so this is never nil
    local machine_default = defaults.get(player, "machines", self.recipe_proto.category)
    local default_proto = machine_default.proto  --[[@as FPMachinePrototype]]

    local success = false
    -- If the default is applicable, just set it straight away
    if self:is_machine_applicable(default_proto) then
        self:change_machine_to_proto(player, default_proto)
        success = true
    -- Otherwise, go up, then down the category to find an alternative
    elseif self:change_machine_by_action(player, "upgrade", default_proto) then
        success = true
    elseif self:change_machine_by_action(player, "downgrade", default_proto) then
        success = true
    end

    if success then self.machine.quality_proto = machine_default.quality end
    return success
end


---@param beacon Beacon?
function Line:set_beacon(beacon)
    self.beacon = beacon  -- can be nil

    if beacon ~= nil then
        self.beacon.parent = self
        beacon.module_set:normalize({compatibility=true, effects=true})
        -- Normalization already summarizes effects
    else
        self:summarize_effects()
    end
end

---@param player LuaPlayer
function Line:setup_beacon(player)
    local beacon_defaults = defaults.get(player, "beacons", nil)
    if beacon_defaults.modules and beacon_defaults.beacon_amount ~= 0 then
        local blank_beacon = Beacon.init(beacon_defaults.proto, self)
        self:set_beacon(blank_beacon)
        blank_beacon:reset(player)
    end
end

function Line:summarize_effects()
    local beacon_effects = (self.beacon) and self.beacon.total_effects or nil
    local merged_effects = util.effects.merge({self.machine.total_effects, beacon_effects})
    local limited_effects, indications = util.effects.limit(merged_effects, self.recipe_proto.maximum_productivity)

    self.total_effects = limited_effects
    self.effects_tooltip = util.effects.format(limited_effects, {indications=indications})
end


---@return PrototypeFilter filter
function Line:compile_machine_filter()
    local compatible_machines = {}

    local machine_category = prototyper.util.find("machines", nil, self.machine.proto.category)
    for _, machine_proto in pairs(machine_category.members) do
        if self:is_machine_applicable(machine_proto) then
            table.insert(compatible_machines, machine_proto.name)
        end
    end

    return {{filter="name", name=compatible_machines}}
end


---@param properties SurfaceProperties?
---@param conditions SurfaceCondition[]
---@return boolean compatible
local function check_compatibility(properties, conditions)
    if not properties or not conditions then return true end
    for _, condition in pairs(conditions) do
        local property = properties[condition.property]
        if property and (property < condition.min or property > condition.max) then
            return false
        end
    end
    return true
end

---@return SurfaceCompatibility compatibility
function Line:get_surface_compatibility()
    -- Determine and save compatibility on the fly when requested
    if self.surface_compatibility == nil then
        local object = self.parent  --[[@as Object]]  -- find the District this is in
        while object.class ~= "District" do object = object.parent  --[[@as District]] end
        local properties = object.location_proto.surface_properties

        local recipe = check_compatibility(properties, self.recipe_proto.surface_conditions)
        local machine = check_compatibility(properties, self.machine.proto.surface_conditions)
        self.surface_compatibility = {recipe=recipe, machine=machine, overall=(recipe and machine)}
    end
    return self.surface_compatibility
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

    -- Reset so solver doesn't have to
    self.products:clear()
    self.byproducts:clear()
    self.ingredients:clear()

    return self.valid
end

return {init = init, unpack = unpack}

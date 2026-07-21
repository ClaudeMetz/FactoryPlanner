local Object = require("backend.data.Object")
local Recipe = require("backend.data.Recipe")
local Machine = require("backend.data.Machine")
local Beacon = require("backend.data.Beacon")

---@class Line: Object, ObjectMethods
---@field class "Line"
---@field parent Floor
---@field next LineObject?
---@field previous LineObject?
---@field recipe Recipe
---@field done boolean
---@field active boolean
---@field percentage number
---@field machine Machine
---@field beacon Beacon?
---@field comment string
---@field total_effects IntegerModuleEffects
---@field effects_tooltip LocalisedString
---@field surface_compatibility SurfaceCompatibility?
---@field products SimpleItem[]
---@field byproducts SimpleItem[]
---@field ingredients SimpleItem[]
---@field production_ratio number
local Line = Object.methods()
Line.__index = Line
script.register_metatable("Line", Line)

---@param recipe_proto FPRecipePrototype?
---@param production_type RecipeProductionType?
---@return Line
local function init(recipe_proto, production_type)
    local object = Object.init({
        recipe = nil,  -- initialized below
        done = false,
        active = true,
        percentage = 100,
        machine = nil,
        beacon = nil,
        comment = "",

        total_effects = nil,
        effects_tooltip = "",
        surface_compatibility = nil,  -- determined on demand

        products = {},
        byproducts = {},
        ingredients = {},
        production_ratio = 0
    }, "Line", Line)  ---@as Line

    if recipe_proto then
        object.recipe = Recipe.init(object, recipe_proto, production_type)
    end

    return object
end


function Line:index()
    OBJECT_INDEX[self.id] = self
    self.recipe:index()
    self.machine:index()
    if self.beacon then self.beacon:index() end
end


-- Returns whether the given machine can be used for this line/recipe
---@param machine_proto FPMachinePrototype
---@return boolean applicable
function Line:is_machine_compatible(machine_proto)
    ---@cast self.recipe.proto FPRecipePrototype
    local type_counts = self.recipe.proto.type_counts

    local valid_ingredient_count = (machine_proto.ingredient_limit >= type_counts.ingredients.items)
    local valid_product_count = (machine_proto.product_limit >= type_counts.products.items)
    local valid_input_channels = (machine_proto.fluid_channels.input >= type_counts.ingredients.fluids)
    local valid_output_channels = (machine_proto.fluid_channels.output >= type_counts.products.fluids)

    return (valid_ingredient_count and valid_product_count and valid_input_channels and valid_output_channels)
end

-- Sets this line's machine to be the given prototype
---@param player LuaPlayer
---@param proto FPMachinePrototype
function Line:change_machine_to_proto(player, proto)
    if not self.machine then
        self.machine = Machine.init(self, proto)
        self.machine:summarize_effects()
    else
        self.machine.proto = proto

        self.machine.module_set:normalize({compatibility=true, trim=true, effects=true})
        if not self:uses_beacon_effects() then self:set_beacon(nil) end
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
    local current_machine_proto = current_proto or self.machine.proto  ---@as FPMachinePrototype
    local category_id = current_machine_proto.category_id

    ---@param new_machine_id integer
    ---@return boolean success
    local function try_machine(new_machine_id)
        -- Assume a match while inside the upgrade/downgrade loop
        current_machine_proto = prototyper.util.find("machines", new_machine_id, category_id) ---@as FPMachinePrototype

        if self:is_machine_compatible(current_machine_proto) then
            self:change_machine_to_proto(player, current_machine_proto)
            return true
        end
        return false
    end

    if action == "upgrade" then
        local max_machine_id = #prototyper.util.find("machines", nil, category_id)--[[@cast -nil]].members
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
    local machine_default = defaults.get(player, "machines", self.recipe.proto.combined_category)
    local default_proto = machine_default.proto  ---@as FPMachinePrototype

    local success = false
    -- If the default is applicable, just set it straight away
    if self:is_machine_compatible(default_proto) then
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
        beacon.parent = self

        -- Reset amount since the user can't change it in the dialog
        if beacon:is_mono_beacon() then beacon.amount = 1 end

        beacon.module_set:normalize({compatibility=true, effects=true})
        -- Normalization already summarizes beacon's effects
    else
        self:summarize_effects()
    end
end

---@param player LuaPlayer
function Line:setup_beacon(player)
    local beacon_defaults = defaults.get(player, "beacons", nil)
    if beacon_defaults.modules and beacon_defaults.beacon_amount ~= 0 then
        local proto = beacon_defaults.proto  ---@as FPBeaconPrototype
        local blank_beacon = Beacon.init(self, proto)
        self:set_beacon(blank_beacon)
        blank_beacon:reset(player)
    end
end

---@return boolean
function Line:uses_beacon_effects()
    ---@cast self.machine.proto FPMachinePrototype
    return self.machine.proto.effect_receiver.uses_beacon_effects
end


function Line:summarize_effects()
    ---@cast self.machine.proto FPMachinePrototype
    ---@cast self.recipe.proto FPRecipePrototype

    local beacon_effects = (self.beacon) and self.beacon.total_effects or nil
    local merged_effects = lib.effects.merge({self.machine.total_effects, beacon_effects})
    local limited_effects, indications = lib.effects.limit(merged_effects, self.machine.proto.effect_receiver)

    local limited_effects_plus = lib.effects.merge({limited_effects, self.recipe.effects})
    -- These bounds are applied after normal limits and recipe effects
    local bounds = {low = 0, high = self.recipe.proto.maximum_productivity}
    limited_effects_plus["productivity"], indications["productivity"] =
        lib.effects.limit_value(limited_effects_plus["productivity"], bounds)

    self.total_effects = limited_effects_plus
    self.effects_tooltip = lib.effects.format(limited_effects_plus, {indications=indications})
end


---@return PrototypeFilter filter
function Line:compile_machine_filter()
    local compatible_machines = {}

    local machine_category = prototyper.util.find("machines", nil, self.machine.proto.combined_category)  ---@as NamedCategory<FPMachinePrototype>

    for _, machine_proto in pairs(machine_category.members) do
        if self:is_machine_compatible(machine_proto) then
            table.insert(compatible_machines, machine_proto.name)
        end
    end

    return {{filter="name", name=compatible_machines}}
end


---@return boolean
function Line:is_temperature_fully_configured()
    ---@cast self.recipe.proto FPRecipePrototype

    for _, ingredient in pairs(self.recipe.proto.ingredients) do
        if not self.recipe:is_temperature_configured(ingredient) then return false end
    end

    local fuel = self.machine.fuel
    if fuel and not fuel:is_temperature_configured() then return false end

    return true
end


---@param properties SurfaceProperties?
---@param conditions SurfaceCondition[]?
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
        local object = self.parent  ---@as Object  -- find the District this is in
        while object.class ~= "District" do object = object.parent--[[@as District]] end
        ---@cast object District

        local properties = object.location_proto.surface_properties
        local recipe = check_compatibility(properties, self.recipe.proto.surface_conditions)
        local machine = check_compatibility(properties, self.machine.proto.surface_conditions)
        self.surface_compatibility = {recipe=recipe, machine=machine, overall=(recipe and machine)}
    end
    return self.surface_compatibility
end


---@param object CopyableObject
---@param tags ActOnLineItem
---@return boolean success
---@return string? error
---@return string? target_class
function Line:paste(object, tags)
    -- The target may also be an ingredient on the line
    local target = self  ---@type Line | SimpleItem
    if tags.item_category and tags.item_index then
        target = self[tags.item_category .. "s"][tags.item_index]
    end

    if target.class == "Line" and (object.class == "Line" or object.class == "Floor") then
        ---@cast object LineObject
        if not self.parent:check_product_compatibility(object--[[@as LineObject]]) then
            return false, "recipe_irrelevant"  -- found no use for the recipe's products
        end

        self.parent:replace(self, object--[[@as LineObject]])
        return true, nil
    elseif target.class == "SimpleItem" and (object.class == "SimpleItem" or object.class =="Fuel") then

        local item = self[tags.item_category .. "s"][tags.item_index]  ---@as SimpleItem]]

        -- Only allow pasting fluid temperature settings
        if object.proto.type ~= "fluid" or item.proto.type ~= "fluid" then
            return false, "incompatible"
        end

        -- SimpleItems will always be a fluid with temperature
        if object.class == "SimpleItem" then
            if object.proto.base_name ~= target.proto.name then return false, "incompatible" end
            if not self.recipe:set_temperature(target.proto, object.proto.temperature) then
                return false, "incompatible"
            end
        else  -- "Fuel"
            if object.proto.name ~= target.proto.name then return false, "incompatible" end
            if not self.recipe:set_temperature(target.proto, object.temperature) then
                return false, "incompatible"
            end
        end

        return true, nil
    else
        return false, "incompatible_class", target.class
    end
end


---@class PackedLine: PackedObject
---@field class "Line"
---@field recipe PackedRecipe
---@field done boolean
---@field active boolean
---@field percentage number
---@field machine PackedMachine
---@field beacon PackedBeacon?
---@field comment string

---@param full boolean
---@return PackedLine packed_self
function Line:pack(full)
    return {
        class = self.class,
        recipe = self.recipe:pack(full),
        done = self.done,
        active = self.active,
        percentage = self.percentage,
        machine = self.machine:pack(full),
        beacon = self.beacon and self.beacon:pack(full),
        comment = self.comment,

        products = (full) and interface.pack_items(self.products) or nil,
        byproducts = (full) and interface.pack_items(self.byproducts) or nil,
        ingredients = (full) and interface.pack_items(self.ingredients) or nil,
    }
end

---@param packed_self PackedLine
---@return Line line
local function unpack(packed_self)
    local unpacked_self = init()  -- initialize empty, overwrite after
    unpacked_self.recipe = Recipe.unpack(packed_self.recipe, unpacked_self)  ---@as Recipe
    unpacked_self.done = packed_self.done
    unpacked_self.active = packed_self.active
    unpacked_self.percentage = packed_self.percentage
    unpacked_self.machine = Machine.unpack(packed_self.machine, unpacked_self)  ---@as Machine
    unpacked_self.beacon = packed_self.beacon and Beacon.unpack(packed_self.beacon, unpacked_self)  ---@as Beacon
    unpacked_self.comment = packed_self.comment

    return unpacked_self
end


---@return boolean valid
function Line:validate()
    self.valid = self.recipe:validate()

    if self.recipe.valid then self.valid = self.machine:validate() and self.valid end

    if self.recipe.valid and self.beacon then self.valid = self.beacon:validate() and self.valid end

    self.surface_compatibility = nil  -- reset cached value

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Line:repair(player)
    self.valid = true

    if not self.recipe.valid then
        self.valid = self.recipe:repair(player)
    end

    if self.valid and not self.machine.valid then
        self.valid = self.machine:repair(player)
    end

    if self.valid and self.beacon and not self.beacon.valid then
        -- Repairing a beacon always either fixes or gets it removed, so no influence on validity
        if not self.beacon:repair(player) then self.beacon = nil end
    end

    return self.valid
end

return {init = init, unpack = unpack}

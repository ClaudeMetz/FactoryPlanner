---@class FPLine
---@field recipe FPRecipe?
---@field active boolean?
---@field done boolean
---@field percentage number
---@field machine FPMachine?
---@field beacon FPBeacon?
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
---@field energy_consumption number
---@field pollution number
---@field Product FPCollection<FPItem>
---@field Byproduct FPCollection<FPItem>
---@field Ingredient FPCollection<FPItem>
---@field priority_product_proto FPItemPrototype
---@field comment string?
---@field production_ratio number?
---@field uncapped_production_ratio number?
---@field subfloor FPFloor?
---@field valid boolean
---@field id integer
---@field gui_position integer
---@field parent FPFloor
---@field class "Line"

-- 'Class' representing an assembly line producing a recipe or representing a subfloor
Line = {}

function Line.init(recipe)
    local is_standalone_line = (recipe ~= nil)

    return {
        recipe = recipe,  -- can be nil
        active = (is_standalone_line) and true or nil,
        done = false,
        percentage = (is_standalone_line) and 100 or nil,
        machine = nil,
        beacon = nil,
        total_effects = nil,
        effects_tooltip = "",
        energy_consumption = 0,
        pollution = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        priority_product_proto = nil,  -- set by the user
        comment = nil,
        production_ratio = (is_standalone_line) and 0 or nil,
        uncapped_production_ratio = (is_standalone_line) and 0 or nil,
        subfloor = nil,
        valid = true,
        id = nil,  -- set by collection
        gui_position = nil,  -- set by collection
        parent = nil,  -- set by parent
        class = "Line"
    }
end


function Line.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Line.remove(self, dataset)
    return Collection.remove(self[dataset.class], dataset)
end

function Line.replace(self, dataset, object)
    object.parent = self
    return Collection.replace(self[dataset.class], dataset, object)
end

function Line.clear(self, class)
    self[class] = Collection.init()
end


function Line.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Line.get_all(self, class)
    return Collection.get_all(self[class])
end

function Line.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Line.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Line.get_by_name(self, class, name)
    return Collection.get_by_name(self[class], name)
end

function Line.get_by_type_and_name(self, class, type, name)
    return Collection.get_by_type_and_name(self[class], type, name)
end


-- Returns whether the given machine can be used for this line/recipe
function Line.is_machine_applicable(self, machine_proto)
    local recipe_proto = self.recipe.proto
    local valid_ingredient_count = (machine_proto.ingredient_limit >= recipe_proto.type_counts.ingredients.items)
    local valid_input_channels = (machine_proto.fluid_channels.input >= recipe_proto.type_counts.ingredients.fluids)
    local valid_output_channels = (machine_proto.fluid_channels.output >= recipe_proto.type_counts.products.fluids)

    return (valid_ingredient_count and valid_input_channels and valid_output_channels)
end

-- Sets this line's machine to be the given prototype
function Line.change_machine_to_proto(self, player, proto)
    if not self.machine then
        self.machine = Machine.init(proto, self)
        ModuleSet.summarize_effects(self.machine.module_set)
    else
        self.machine.proto = proto

        ModuleSet.normalize(self.machine.module_set, {compatibility=true, trim=true, effects=true})
        if self.machine.proto.allowed_effects == nil then Line.set_beacon(self, nil) end
    end

    -- Make sure the machine's fuel still applies
    Machine.normalize_fuel(self.machine, player)

    return true
end

-- Up- or downgrades this line's machine, if possible
-- Returns false if no compatible machine can be found, true otherwise
function Line.change_machine_by_action(self, player, action, current_proto)
    local current_machine_proto = current_proto or self.machine.proto
    local category_machines = PROTOTYPE_MAPS.machines[current_machine_proto.category].members

    if action == "upgrade" then
        local max_machine_id = #category_machines

        while current_machine_proto.id < max_machine_id do
            current_machine_proto = category_machines[current_machine_proto.id + 1]

            if Line.is_machine_applicable(self, current_machine_proto) then
                Line.change_machine_to_proto(self, player, current_machine_proto)
                return true
            end
        end
    else  -- action == "downgrade"
        while current_machine_proto.id > 1 do
            current_machine_proto = category_machines[current_machine_proto.id - 1]

            if Line.is_machine_applicable(self, current_machine_proto) then
                Line.change_machine_to_proto(self, player, current_machine_proto)
                return true
            end
        end
    end

    return false  -- if the above loop didn't return, no machine could be found, so we return false
end

-- Changes this line's machine to its default, if possible
-- Returns false if no compatible machine can be found, true otherwise
function Line.change_machine_to_default(self, player)
    local machine_category_id = PROTOTYPE_MAPS.machines[self.recipe.proto.category].id
    -- All categories are guaranteed to have at least one machine, so this is never nil
    local default_machine_proto = prototyper.defaults.get(player, "machines", machine_category_id)

    -- If the default is applicable, just set it straight away
    if Line.is_machine_applicable(self, default_machine_proto) then
        Line.change_machine_to_proto(self, player, default_machine_proto)
        return true

    -- Otherwise, go up, then down the category to find an alternative
    elseif Line.change_machine_by_action(self, player, "upgrade", default_machine_proto) then
        return true
    elseif Line.change_machine_by_action(self, player, "downgrade", default_machine_proto) then
        return true

    else  -- if no machine in the whole category is applicable, return false
        return false
    end
end


function Line.set_beacon(self, beacon)
    self.beacon = beacon  -- can be nil

    if beacon ~= nil then
        self.beacon.parent = self
        ModuleSet.normalize(self.beacon.module_set, {sort=true, effects=true})
    else
        Line.summarize_effects(self)
    end
end


function Line.apply_mb_defaults(self, player)
    ModuleSet.clear(self.machine.module_set)
    Line.set_beacon(self, nil)

    local mb_defaults = data_util.preferences(player).mb_defaults
    local machine_module, secondary_module = mb_defaults.machine, mb_defaults.machine_secondary
    local module_set, module_limit = self.machine.module_set, self.machine.proto.module_limit
    local message = nil

    if machine_module and Machine.check_module_compatibility(self.machine, machine_module) then
        ModuleSet.add(module_set, machine_module, module_limit)

    elseif secondary_module and Machine.check_module_compatibility(self.machine, secondary_module) then
        ModuleSet.add(module_set, secondary_module, module_limit)

    elseif machine_module then  -- only show an error if any module default is actually set
        message = {text={"fp.warning_module_not_compatible", {"fp.pl_module", 1}}, category="warning"}
    end
    ModuleSet.summarize_effects(self.machine.module_set)

    -- Add default beacon modules, if desired by the user
    local beacon_module_proto, beacon_count = mb_defaults.beacon, mb_defaults.beacon_count
    if BEACON_OVERLOAD_ACTIVE then beacon_count = 1 end
    local beacon_proto = prototyper.defaults.get(player, "beacons")  -- this will always exist

    if beacon_module_proto ~= nil and beacon_count ~= nil then
        local blank_beacon = Beacon.init(beacon_proto, beacon_count, nil, self)

        if Beacon.check_module_compatibility(blank_beacon, beacon_module_proto) then
            ModuleSet.add(blank_beacon.module_set, beacon_module_proto, beacon_proto.module_limit)
            Line.set_beacon(self, blank_beacon)  -- summarizes effects on its own

        elseif message == nil then  -- don't overwrite previous message, if it exists
            message = {text={"fp.warning_module_not_compatible", {"fp.pl_beacon", 1}}, category="warning"}
        end
    end

    return message
end


function Line.summarize_effects(self)
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
    self.effects_tooltip = data_util.format_module_effects(effects, true)
end


function Line.paste(self, object)
    if object.class == "Line" then
        if self.parent.level > 1 then  -- make sure the recipe is allowed on this floor
            local relevant_line = (object.subfloor) and object.subfloor.defining_line or object
            if not data_util.check_product_compatibiltiy(self.parent, relevant_line.recipe) then
                return false, "recipe_irrelevant"  -- found no use for the recipe's products
            end
        end

        if object.subfloor then Subfactory.add_subfloor_references(self.parent.parent, object) end
        Floor.insert_at(self.parent, self.gui_position + 1, object)
        return true, nil
    else
        return false, "incompatible_class"
    end
end


function Line.pack(self)
    local packed_line = {
        comment = self.comment,
        class = self.class
    }

    if self.subfloor ~= nil then
        packed_line.subfloor = Floor.pack(self.subfloor)
    else
        packed_line.recipe = Recipe.pack(self.recipe)

        packed_line.active = self.active
        packed_line.done = self.done
        packed_line.percentage = self.percentage

        packed_line.machine = Machine.pack(self.machine)
        packed_line.beacon = (self.beacon) and Beacon.pack(self.beacon) or nil

        -- If this line has no priority_product, the function will return nil
        local priority_proto = self.priority_product_proto
        if priority_proto ~= nil then
            packed_line.priority_product_proto = prototyper.util.simplify_prototype(priority_proto, priority_proto.type)
        end

        packed_line.Product = Collection.pack(self.Product, Item)  -- conserve for cloning
    end

    return packed_line
end

function Line.unpack(packed_self, parent_level)
    if packed_self.subfloor ~= nil then
        local self = Line.init()  -- empty line which gets the subfloor
        local subfloor = Floor.init()  -- empty floor to be manually adjusted as necessary

        subfloor.level = parent_level + 1
        subfloor.origin_line = self
        self.subfloor = subfloor

        Floor.unpack(packed_self.subfloor, subfloor)
        subfloor.defining_line = subfloor.Line.datasets[1]

        return self
    else
        local self = Line.init(packed_self.recipe)

        self.active = packed_self.active
        self.done = packed_self.done
        self.percentage = packed_self.percentage

        self.machine = Machine.unpack(packed_self.machine)
        self.machine.parent = self

        self.beacon = (packed_self.beacon) and Beacon.unpack(packed_self.beacon) or nil
        if self.beacon then self.beacon.parent = self end
        -- Effects summarized by the ensuing validation

        -- The prototype will be automatically unpacked by the validation process
        self.priority_product_proto = packed_self.priority_product_proto
        self.comment = packed_self.comment

        self.Product = Collection.unpack(packed_self.Product, self, Item)  -- conserved for cloning

        return self
    end
end


-- Needs validation: recipe, machine, beacon, priority_product_proto, subfloor
function Line.validate(self)
    self.valid = true

    if self.subfloor then  -- when this line has a subfloor, only the subfloor need to be checked
        self.valid = Floor.validate(self.subfloor) and self.valid

    else
        self.valid = Recipe.validate(self.recipe) and self.valid

        self.valid = Machine.validate(self.machine) and self.valid

        if self.beacon then self.valid = Beacon.validate(self.beacon) and self.valid end

        if self.priority_product_proto then
            self.priority_product_proto = prototyper.util.validate_prototype_object(self.priority_product_proto, "type")
            self.valid = (not self.priority_product_proto.simplified) and self.valid
        end

        self.valid = Collection.validate_datasets(self.Product, Item) and self.valid  -- conserved for cloning

        -- Effects summarized by machine/beacon validation
    end

    return self.valid
end

-- Needs repair: recipe, machine, beacon, priority_product_proto, subfloor
function Line.repair(self, player)
    self.valid = true

    if self.subfloor then
        local subfloor = self.subfloor
        if not subfloor.valid then
            if not subfloor.defining_line.valid then
                self.valid = false  -- if the defining line is invalid, this whole thing is toast
            else
                Floor.repair(self.subfloor, player)
            end
        end

    else
        if not self.recipe.valid then
            self.valid = Recipe.repair(self.recipe, nil)
        end

        if self.valid and not self.machine.valid then
            self.valid = Machine.repair(self.machine, player)
        end

        if self.valid and self.beacon and not self.beacon.valid then
            -- Repairing a beacon always either fixes or gets it removed, so no influence on validity
            if not Beacon.repair(self.beacon, nil) then self.beacon = nil end
        end

        if self.valid and self.priority_product_proto and self.priority_product_proto.simplified then
            self.priority_product_proto = nil
        end

        -- effects summarized by machine/beacon repair
    end

    -- Clear item prototypes so we don't need to rely on the solver to remove them
    Line.clear(self, "Product")
    Line.clear(self, "Byproduct")
    Line.clear(self, "Ingredient")

    return self.valid
end

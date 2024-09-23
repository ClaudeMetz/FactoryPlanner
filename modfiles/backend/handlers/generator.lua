local generator_util = require("backend.handlers.generator_util")

local generator = {
    machines = {},
    recipes = {},
    items = {},
    fuels = {},
    belts = {},
    wagons = {},
    modules = {},
    beacons = {},
    locations = {},
    qualities = {}
}


---@class FPPrototype
---@field id integer
---@field data_type DataType
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath

---@class FPPrototypeWithCategory: FPPrototype
---@field category_id integer

---@alias AnyFPPrototype FPPrototype | FPPrototypeWithCategory


---@param list AnyNamedPrototypes
---@param prototype FPPrototype
---@param category string?
local function insert_prototype(list, prototype, category)
    if category == nil then
        ---@cast list NamedPrototypes<FPPrototype>
        list[prototype.name] = prototype
    else
        ---@cast list NamedPrototypesWithCategory<FPPrototype>
        list[category] = list[category] or { name = category, members = {} }
        list[category].members[prototype.name] = prototype
    end
end

---@param list AnyNamedPrototypes
---@param name string
---@param category string?
local function remove_prototype(list, name, category)
    if category == nil then
        ---@cast list NamedPrototypes<FPPrototype>
        list[name] = nil
    else
        ---@cast list NamedPrototypesWithCategory<FPPrototype>
        list[category].members[name] = nil
        if next(list[category].members) == nil then list[category] = nil end
    end
end


---@class FPMachinePrototype: FPPrototypeWithCategory
---@field data_type "machines"
---@field category string
---@field elem_type ElemType
---@field quality_category QualityCategory
---@field ingredient_limit integer
---@field fluid_channels FluidChannels
---@field speed double
---@field energy_type "burner" | "electric" | "void"
---@field energy_usage double
---@field energy_drain double
---@field emissions_per_joule EmissionsMap
---@field emissions_per_second EmissionsMap
---@field burner MachineBurner?
---@field built_by_item FPItemPrototype?
---@field effect_receiver EffectReceiver?
---@field allowed_effects AllowedEffects
---@field module_limit integer
---@field surface_conditions SurfaceCondition[]
---@field resource_drain_rate number?

---@class FluidChannels
---@field input integer
---@field output integer

---@class MachineBurner
---@field effectivity double
---@field categories { [string]: boolean }
---@field combined_category string

---@alias EmissionsMap { [string]: double }
---@alias QualityCategory ("assembling-machine" | "mining-drill")?

-- Generates a table containing all machines for all categories
---@return NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.generate()
    local machines = {}  ---@type NamedPrototypesWithCategory<FPMachinePrototype>

    ---@param category string
    ---@param proto LuaEntityPrototype
    ---@param quality_category QualityCategory
    ---@return FPMachinePrototype?
    local function generate_category_entry(category, proto, quality_category)
        -- First, determine if there is a valid sprite for this machine
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite == nil then return end

        -- Determine data related to the energy source
        local energy_type, emissions_per_joule = "", {}  -- no emissions if no energy source is present
        local burner = nil  ---@type MachineBurner
        local energy_usage, energy_drain = (proto.energy_usage or proto.get_max_energy_usage() or 0), 0

        -- Determine the name of the item that actually builds this machine for the item requester
        -- There can technically be more than one, but bots use the first one, so I do too
        local built_by_item = (proto.items_to_place_this) and proto.items_to_place_this[1].name or nil

        -- Determine the details of this entities energy source
        local burner_prototype, fluid_burner_prototype = proto.burner_prototype, proto.fluid_energy_source_prototype
        if burner_prototype then
            energy_type = "burner"
            emissions_per_joule = burner_prototype.emissions_per_joule
            burner = {effectivity = burner_prototype.effectivity, categories = burner_prototype.fuel_categories,
                combined_category = ""}
            for fuel_category, _ in pairs(burner_prototype.fuel_categories) do
                burner.combined_category = burner.combined_category .. fuel_category
            end

        -- Only supports fluid energy that burns_fluid for now, as it works the same way as solid burners
        -- Also doesn't respect scale_fluid_usage and fluid_usage_per_tick for now, let the reports come
        elseif fluid_burner_prototype then
            emissions_per_joule = fluid_burner_prototype.emissions_per_joule

            if fluid_burner_prototype.burns_fluid and not fluid_burner_prototype.fluid_box.filter then
                energy_type = "burner"
                burner = {effectivity = fluid_burner_prototype.effectivity, categories = {["fluid-fuel"] = true},
                    combined_category = "fluid-fuel"}

            else  -- Avoid adding this type of complex fluid energy as electrical energy
                energy_type = "void"
            end

        elseif proto.electric_energy_source_prototype then
            energy_type = "electric"
            energy_drain = proto.electric_energy_source_prototype.drain
            emissions_per_joule = proto.electric_energy_source_prototype.emissions_per_joule

        elseif proto.void_energy_source_prototype then
            energy_type = "void"
            emissions_per_joule = proto.void_energy_source_prototype.emissions_per_joule
        end

        -- Determine fluid input/output channels
        local fluid_channels = {input = 0, output = 0}
        if fluid_burner_prototype then fluid_channels.input = fluid_channels.input - 1 end

        for _, fluidbox in pairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" then
                fluid_channels.output = fluid_channels.output + 1
            else  -- "input" and "input-output"
                fluid_channels.input = fluid_channels.input + 1
            end
        end

        local effect_receiver = proto.effect_receiver or {
            base_effects = {},
            uses_module_effects = false,
            uses_beacon_effects = false,
            uses_surface_effects = false
        }

        local machine = {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = sprite,
            category = category,
            elem_type = "entity",
            quality_category = quality_category,
            ingredient_limit = (proto.ingredient_count or 255),
            fluid_channels = fluid_channels,
            speed = proto.get_crafting_speed(),
            energy_type = energy_type,
            energy_usage = energy_usage,
            energy_drain = energy_drain,
            emissions_per_joule = emissions_per_joule,
            emissions_per_second = proto.emissions_per_second or {},
            burner = burner,
            built_by_item = built_by_item,
            effect_receiver = effect_receiver,
            allowed_effects = proto.allowed_effects or {},
            module_limit = (proto.module_inventory_size or 0),
            surface_conditions = proto.surface_conditions
        }
        generator_util.check_machine_effects(machine)

        return machine
    end

    local biggest_chest = nil

    for _, proto in pairs(prototypes.entity) do
        if proto.crafting_categories and not proto.hidden and proto.energy_usage ~= nil
                and not generator_util.is_irrelevant_machine(proto) then
            for category, _ in pairs(proto.crafting_categories) do
                local machine = generate_category_entry(category, proto, "assembling-machine")
                if machine then insert_prototype(machines, machine, machine.category) end
            end

        elseif proto.type == "mining-drill" and not proto.hidden then
            for category, _ in pairs(proto.resource_categories) do
                local machine = generate_category_entry(category, proto, "mining-drill")
                if machine then
                    machine.speed = proto.mining_speed
                    machine.resource_drain_rate = proto.resource_drain_rate_percent / 100
                    insert_prototype(machines, machine, category)
                end
            end

        elseif proto.type == "offshore-pump" and not proto.hidden then
            local fluid_box = proto.fluidbox_prototypes[1]
            local fixed_fluid = (fluid_box and fluid_box.filter) and fluid_box.filter.name or nil
            local category = (fixed_fluid) and ("offshore-pump-" .. fixed_fluid) or "offshore-pump"
            local machine = generate_category_entry(category, proto, nil)
            if machine then
                machine.speed = proto.pumping_speed
                insert_prototype(machines, machine, category)
            end

        elseif proto.type == "agricultural-tower" and not proto.hidden then
            local machine = generate_category_entry(proto.type, proto, nil)
            if machine then
                local growth_area_width = (proto.growth_grid_tile_size * 2) + 1
                local available_tiles = growth_area_width * growth_area_width - 1
                machine.speed = available_tiles
                machine.energy_usage = 0  -- implemented later: energy_usage, crane_energy_usage
                insert_prototype(machines, machine, proto.type)
            end

        elseif proto.type == "container" and not proto.hidden then
            -- Just find the biggest container as a spoilage machine
            local size = proto.get_inventory_size(defines.inventory.chest)
            local current_size = biggest_chest and biggest_chest.get_inventory_size(defines.inventory.chest) or 0
            if current_size < size then biggest_chest = proto end
        end

        -- Add machines that produce steam (ie. boilers)
        --[[ for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" and fluidbox.filter
                    and fluidbox.filter.name == "steam" and proto.target_temperature ~= nil then
                -- Exclude any boilers that use heat as their energy source
                if proto.burner_prototype or proto.electric_energy_source_prototype then
                    -- Find the corresponding input fluidbox
                    local input_fluidbox = nil  ---@type LuaFluidBoxPrototype
                    for _, fb in ipairs(proto.fluidbox_prototypes) do
                        if fb.production_type == "input-output" or fb.production_type == "input" then
                            input_fluidbox = fb
                            break
                        end
                    end

                    -- Add the machine if it has a valid input fluidbox
                    if input_fluidbox ~= nil then
                        local category = "steam-" .. proto.target_temperature
                        local machine = generate_category_entry(category, proto)
                        if machine then
                            local temp_diff = proto.target_temperature - input_fluidbox.filter.default_temperature
                            local energy_per_unit = input_fluidbox.filter.heat_capacity * temp_diff
                            machine.speed = machine.energy_usage / energy_per_unit

                            insert_prototype(machines, machine, machine.category)

                            -- Add every boiler to the general steam category (steam without temperature)
                            local general_machine = ftable.deep_copy(machine)
                            general_machine.category = "general-steam"
                            insert_prototype(machines, general_machine, general_machine.category)
                        end
                    end
                end
            end
        end ]]
    end

    if biggest_chest then
        local machine = generate_category_entry("purposeful-spoiling", biggest_chest, nil)
        if machine then
            machine.speed, machine.energy_usage = 1, 0
            insert_prototype(machines, machine, "purposeful-spoiling")
        end
    end

    return machines
end

---@param machines NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.second_pass(machines)
    -- Go over all recipes to find unused categories
    local used_category_names = {}  ---@type { [string]: boolean }
    for _, recipe_proto in pairs(storage.prototypes.recipes) do
        used_category_names[recipe_proto.category] = true
    end

    for _, machine_category in pairs(machines) do
        if used_category_names[machine_category.name] == nil then
            machines[machine_category.name] = nil
        end
    end

    -- Filter out burner machines that don't have any valid fuel categories
    for _, machine_category in pairs(machines) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.energy_type == "burner" then
                local category_found = false
                for fuel_category in pairs(machine_proto.burner.categories) do
                    if storage.prototypes.fuels[fuel_category] then category_found = true; break end
                end
                if not category_found then remove_prototype(machines, machine_proto.name, machine_category.name) end
            end
        end

        -- If the category ends up empty because of this, make sure to remove it
        if not next(machine_category.members) then machines[machine_category.name] = nil end
    end


    -- Replace built_by_item names with prototype references
    local item_prototypes = storage.prototypes.items["item"].members  ---@type { [string]: FPItemPrototype }
    for _, machine_category in pairs(machines) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.built_by_item then
                machine_proto.built_by_item = item_prototypes[machine_proto.built_by_item]
            end
        end
    end
end


---@class FPRecipePrototype: FPPrototype
---@field data_type "recipes"
---@field category string
---@field energy double
---@field emissions_multiplier double
---@field ingredients Ingredient[]
---@field products FormattedProduct[]
---@field main_product FormattedProduct?
---@field allowed_effects AllowedEffects?
---@field maximum_productivity double
---@field type_counts { ingredients: ItemTypeCounts, products: ItemTypeCounts }
---@field catalysts { ingredients: Ingredient[], products: FormattedProduct[] }
---@field surface_conditions SurfaceCondition[]?
---@field recycling boolean
---@field barreling boolean
---@field enabling_technologies string[]
---@field custom boolean
---@field enabled_from_the_start boolean
---@field hidden boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup
---@field tooltip LocalisedString?

-- Returns all standard recipes + custom mining, steam and rocket recipes
---@return NamedPrototypes<FPRecipePrototype>
function generator.recipes.generate()
    local recipes = {}   ---@type NamedPrototypes<FPRecipePrototype>

    ---@return FPRecipePrototype
    local function custom_recipe()
        local recipe = {
            custom = true,
            enabled_from_the_start = true,
            hidden = false,
            maximum_productivity = math.huge,
            type_counts = {},
            catalysts = {products={}, ingredients={}},
            emissions_multiplier = 1
        }
        generator_util.add_default_groups(recipe)
        return recipe
    end


    -- Determine researchable recipes
    local researchable_recipes = {}  ---@type { [string]: string[] }
    local tech_filter = {{filter="hidden", invert=true}, {filter="has-effects", mode="and"}}
    for _, tech_proto in pairs(prototypes.get_technology_filtered(tech_filter)) do
        for _, effect in pairs(tech_proto.effects) do
            if effect.type == "unlock-recipe" then
                local recipe_name = effect.recipe
                researchable_recipes[recipe_name] = researchable_recipes[recipe_name] or {}
                table.insert(researchable_recipes[recipe_name], tech_proto.name)
            end
        end
    end

    -- Determine which plant is created by which seed
    local plant_seed_map = {}
    for _, item_proto in pairs(prototypes.item) do
        if item_proto.plant_result then
            plant_seed_map[item_proto.plant_result.name] = item_proto.name
        end
    end

    -- Add all standard recipes
    local recipe_filter = {{filter="energy", comparison=">", value=0},
        {filter="energy", comparison="<", value=1e+21, mode="and"}}
    for recipe_name, proto in pairs(prototypes.get_recipe_filtered(recipe_filter)) do
        local machine_category = storage.prototypes.machines[proto.category]  ---@type { [string]: FPMachinePrototype }
        -- Avoid any recipes that have no machine to produce them, or are irrelevant
        if machine_category ~= nil and not generator_util.is_irrelevant_recipe(proto) and not proto.is_parameter then
            local recipe = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "recipe/" .. proto.name,
                category = proto.category,
                energy = proto.energy,
                emissions_multiplier = proto.emissions_multiplier,
                allowed_effects = proto.allowed_effects or {},
                maximum_productivity = proto.maximum_productivity,
                type_counts = {},  -- filled out by format_* below
                catalysts = {products={}, ingredients={}},  -- filled out by format_* below
                surface_conditions = proto.surface_conditions,
                recycling = generator_util.is_recycling_recipe(proto),
                barreling = generator_util.is_compacting_recipe(proto),
                enabling_technologies = researchable_recipes[recipe_name],  -- can be nil
                custom = false,
                enabled_from_the_start = proto.enabled,
                hidden = proto.hidden,
                order = proto.order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup)
            }

            generator_util.format_recipe(recipe, proto.products, proto.main_product, proto.ingredients)
            insert_prototype(recipes, recipe, nil)
        end
    end

    for _, proto in pairs(prototypes.entity) do
        if proto.type == "resource" and not proto.hidden then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.localised_name = {"", proto.localised_name, " ", {"fp.mining_recipe"}}
            recipe.sprite = products[1].type .. "/" .. products[1].name
            recipe.order = proto.order
            recipe.category = proto.resource_category

            local ingredients = {{type="entity", name="custom-" .. proto.name, amount=1}}

            if not proto.infinite_resource then
                -- Set energy to mining time so the forumla for the machine_count works out
                recipe.energy = proto.mineable_properties.mining_time

                -- Add mining fluid, if required
                if proto.mineable_properties.required_fluid then
                    table.insert(ingredients, {
                        type = "fluid",
                        name = proto.mineable_properties.required_fluid,
                        -- fluid_amount is given for a 'set' of mining ops, with a set being 10 ore
                        amount = proto.mineable_properties.fluid_amount / 10
                    })
                end
            else
                recipe.energy = 0
                ingredients[1].amount = 0
            end

            generator_util.format_recipe(recipe, products, products[1], ingredients)
            insert_prototype(recipes, recipe, nil)

            ::incompatible_proto::

        -- Add offshore pump recipes based on fixed fluids
        elseif proto.type == "offshore-pump" and not proto.hidden then
            local fluid_box = proto.fluidbox_prototypes[1]
            local fixed_fluid = (fluid_box and fluid_box.filter) and fluid_box.filter.name or nil
            if fixed_fluid then
                local fluid = prototypes.fluid[fixed_fluid]

                local recipe = custom_recipe()
                recipe.name = "impostor-" .. fluid.name .. "-" .. proto.name
                recipe.localised_name = {"", fluid.localised_name, " ", {"fp.pumping_recipe"}}
                recipe.sprite = "fluid/" .. fluid.name
                recipe.order = proto.order
                recipe.category = "offshore-pump-" .. fluid.name
                recipe.energy = 1

                local products = {{type="fluid", name=fluid.name, amount=60}}
                generator_util.format_recipe(recipe, products, products[1], {})
                insert_prototype(recipes, recipe, nil)
            end

        -- Add agricultural tower recipes
        elseif proto.type == "plant" and not proto.hidden then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end
            local seed_name = plant_seed_map[proto.name]
            if not seed_name then goto incompatible_proto end

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.localised_name = {"", proto.localised_name, " ", {"fp.planting_recipe"}}
            recipe.sprite = products[1].type .. "/" .. products[1].name
            recipe.order = proto.order
            recipe.category = "agricultural-tower"
            recipe.energy = 0

            -- Deal with proto.harvest_emissions + proto.emissions_per_second somehow, probably on machine?

            local ingredients = {
                {type="item", name=seed_name, amount=1},
                {type="entity", name="custom-agriculture-square", amount=(proto.growth_ticks / 60)}
            }
            generator_util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)

            ::incompatible_proto::

        elseif proto.type == "rocket-silo" and not proto.hidden then
            local parts_recipe = prototypes.recipe[proto.fixed_recipe]

            -- Add special research rocket recipe
            local research_recipe = custom_recipe()
            local research_products = proto.rocket_entity_prototype.research_products
            if research_products == nil then goto incompatible_proto end
            local main_proto = prototypes.item[research_products[1].name]

            research_recipe.name = "impostor-" .. main_proto.name .. "-rocket"
            research_recipe.localised_name = {"", main_proto.localised_name, " ", {"fp.research_rocket"}}
            research_recipe.sprite = "item/" .. main_proto.name
            research_recipe.order = parts_recipe.order .. "-" .. proto.order .. "-a"
            research_recipe.category = parts_recipe.category
            research_recipe.energy = parts_recipe.energy * proto.rocket_parts_required

            generator_util.format_recipe(research_recipe, research_products,
                research_products[1], parts_recipe.ingredients)
            generator_util.multiply_recipe_items(research_recipe.ingredients, proto.rocket_parts_required)
            insert_prototype(recipes, research_recipe, nil)

            -- Add convenience recipe to build whole rocket instead of parts
            local rocket_recipe = custom_recipe()

            rocket_recipe.name = "impostor-" .. proto.name .. "-rocket"
            rocket_recipe.localised_name = {"", proto.localised_name, " ", {"fp.launch"}}
            rocket_recipe.sprite = "fp_silo_rocket"
            rocket_recipe.order = parts_recipe.order .. "-" .. proto.order .. "-b"
            rocket_recipe.category = parts_recipe.category
            rocket_recipe.energy = parts_recipe.energy * proto.rocket_parts_required

            local rocket_products = {{type="entity", name="custom-silo-rocket", amount=1}}
            generator_util.format_recipe(rocket_recipe, rocket_products,
                rocket_products[1], parts_recipe.ingredients)
            generator_util.multiply_recipe_items(rocket_recipe.ingredients, proto.rocket_parts_required)
            insert_prototype(recipes, rocket_recipe, nil)

            ::incompatible_proto::
        end

        -- Add a recipe for producing steam from a boiler
        --[[ local existing_recipe_names = {}  ---@type { [string]: boolean }
        for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" and fluidbox.filter
                and fluidbox.filter.name == "steam" and proto.target_temperature ~= nil then
                -- Exclude any boilers that use heat or fluid as their energy source
                if proto.burner_prototype or proto.electric_energy_source_prototype then
                    local temperature = proto.target_temperature
                    local recipe_name = "impostor-steam-" .. temperature

                    -- Prevent duplicate recipes, in case more than one boiler produces the same temperature of steam
                    if existing_recipe_names[recipe_name] == nil then
                        existing_recipe_names[recipe_name] = true

                        local recipe = custom_recipe()
                        recipe.name = recipe_name
                        recipe.localised_name = {"fp.fluid_at_temperature", {"fluid-name.steam"},
                            temperature, {"fp.unit_celsius"}}
                        recipe.sprite = "fluid/steam"
                        recipe.category = "steam-" .. temperature
                        recipe.order = "z-" .. temperature
                        recipe.energy = 1

                        local ingredients = {{type="fluid", name="water", amount=60}}
                        local products = {{type="fluid", name="steam", amount=60, temperature=temperature, ignored_by_productivity=60}}
                        generator_util.format_recipe(recipe, products, products[1], ingredients)

                        insert_prototype(recipes, recipe, nil)
                    end
                end
            end
        end ]]
    end

    -- Add offshore pump recipes based on fluid tiles
    local pumped_fluids = {}
    for _, proto in pairs(prototypes.tile) do
        if proto.fluid and not pumped_fluids[proto.fluid.name] and not proto.hidden then
            pumped_fluids[proto.fluid.name] = true

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            recipe.localised_name = {"", proto.fluid.localised_name, " ", {"fp.pumping_recipe"}}
            recipe.sprite = "fluid/" .. proto.fluid.name
            recipe.order = proto.order
            recipe.category = "offshore-pump"
            recipe.energy = 1

            local products = {{type="fluid", name=proto.fluid.name, amount=60}}
            local ingredients = {{type="entity", name="custom-" .. proto.name, amount=60}}
            generator_util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)
        end
    end

    -- Add purposeful spoiling recipes
    for _, proto in pairs(prototypes.item) do
        if proto.get_spoil_ticks() > 0 and proto.spoil_result then
            local recipe = custom_recipe()
            recipe.name = "impostor-spoiling-" .. proto.name
            recipe.localised_name = {"", proto.spoil_result.localised_name, " ", {"fp.spoiling_recipe"}}
            recipe.sprite = "item/" .. proto.spoil_result.name
            recipe.order = proto.spoil_result.order
            recipe.category = "purposeful-spoiling"
            recipe.energy = 0

            local products = {{type="item", name=proto.spoil_result.name, amount=1}}
            local ingredients = {{type="item", name=proto.name, amount=1}}
            generator_util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)
        end
    end

    -- Add a general steam recipe that works with every boiler
    --[[ if prototypes.fluid["steam"] then  -- make sure the steam prototype exists
        local recipe = custom_recipe()
        recipe.name = "fp-general-steam"
        recipe.localised_name = {"fluid-name.steam"}
        recipe.sprite = "fluid/steam"
        recipe.category = "general-steam"
        recipe.order = "z-0"
        recipe.energy = 1

        local ingredients = {{type="fluid", name="water", amount=60}}
        local products = {{type="fluid", name="steam", amount=60, ignored_by_productivity=60}}
        generator_util.format_recipe(recipe, products, products[1], ingredients)

        insert_prototype(recipes, recipe, nil)
    end ]]

    -- Custom handling for Space Exploration Arcosphere recipes
    --[[ local se_split_recipes = {"se-arcosphere-fracture", "se-naquium-processor", "se-naquium-tessaract",
        "se-space-dilation-data", "se-space-fold-data", "se-space-injection-data", "se-space-warp-data"}
    for _, recipe_name in pairs(se_split_recipes) do
        local recipe, alt_recipe = recipes[recipe_name], recipes[recipe_name .. "-alt"]
        if recipe and alt_recipe then
            recipe.custom = true
            generator_util.combine_recipes(recipe, alt_recipe)
            generator_util.multiply_recipe(recipe, 0.5)
            remove_prototype(recipes, alt_recipe.name, nil)
        end
    end ]]

    return recipes
end

---@param recipes NamedPrototypes<FPRecipePrototype>
function generator.recipes.second_pass(recipes)
    local machines = storage.prototypes.machines
    for _, recipe in pairs(recipes) do
        -- Check again if all recipes still have a machine to produce them after machine second pass
        if not machines[recipe.category] then
            remove_prototype(recipes, recipe.name, nil)
        elseif recipe.custom then
            recipe.tooltip = generator_util.recipe_tooltip(recipe)
        end
    end
end


---@class FPItemPrototype: FPPrototypeWithCategory
---@field data_type "items"
---@field type "item" | "fluid" | "entity"
---@field hidden boolean
---@field stack_size uint?
---@field weight double?
---@field ingredient_only boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup
---@field tooltip LocalisedString?
---@field fixed_unit LocalisedString?

---@class RelevantItem
---@field proto RecipeItem
---@field is_product boolean

---@alias RelevantItems { [ItemType]: { [ItemName]: RelevantItem } }

-- Returns all relevant items and fluids
---@return NamedPrototypesWithCategory<FPItemPrototype>
function generator.items.generate()
    local items = {}   ---@type NamedPrototypesWithCategory<FPItemPrototype>

    ---@param table RelevantItems
    ---@param item RelevantItem
    local function add_item(table, item)
        local type = item.proto.type
        local name = item.proto.name
        table[type] = table[type] or {}
        table[type][name] = table[type][name] or {}
        local item_details = table[type][name]
        -- Determine whether this item is used as a product at least once
        item_details.is_product = item_details.is_product or item.is_product
    end

    -- Create a table containing every item that is either a product or an ingredient to at least one recipe
    local relevant_items = {}  ---@type RelevantItems
    for _, recipe_proto in pairs(storage.prototypes.recipes) do
        for _, product in pairs(recipe_proto.products) do
            add_item(relevant_items, {proto=product, is_product=true})
        end
        for _, ingredient in pairs(recipe_proto.ingredients) do
            add_item(relevant_items, {proto=ingredient, is_product=false})
        end
    end


    -- Build custom items, representing in-world entities mostly
    local custom_items, rocket_parts = {}, {}

    for _, proto in pairs(prototypes.entity) do
        if proto.type == "resource" and not proto.hidden then
            local item_name = "custom-" .. proto.name
            custom_items[item_name] = {
                name = item_name,
                localised_name = {"", proto.localised_name, " ", {"fp.deposit"}},
                sprite = "entity/" .. proto.name,
                hidden = true,
                order = proto.order
            }
            generator_util.add_default_groups(custom_items[item_name])

        -- Mark rocket silo part items here so they can be marked as non-hidden
        elseif proto.type == "rocket-silo" and not proto.hidden then
            local parts_recipe = prototypes.recipe[proto.fixed_recipe]
            rocket_parts[parts_recipe.main_product.name] = true
        end
    end

    local pumped_fluids = {}
    for _, proto in pairs(prototypes.tile) do
        if proto.fluid and not pumped_fluids[proto.fluid.name] and not proto.hidden then
            pumped_fluids[proto.fluid.name] = true

            local item_name = "custom-" .. proto.name
            custom_items[item_name] = {
                name = item_name,
                localised_name = {"", proto.localised_name, " ", {"fp.lake"}},
                sprite = "tile/" .. proto.name,
                hidden = true,
                order = proto.order
            }
            generator_util.add_default_groups(custom_items[item_name])
        end
    end

    -- Only need one square item for all agricultural towers
    custom_items["custom-agriculture-square"] = {
        name = "custom-agriculture-square",
        localised_name = {"fp.agriculture_square"},
        sprite = "fp_agriculture_square",
        hidden = true,
        order = "z",
        fixed_unit = {"fp.agriculture_unit"}
    }
    generator_util.add_default_groups(custom_items["custom-agriculture-square"])

    -- Only need one rocket item for all silos/recipes
    custom_items["custom-silo-rocket"] = {
        name = "custom-silo-rocket",
        localised_name = {"", {"entity-name.rocket"}, " ", {"fp.launch"}},
        sprite = "fp_silo_rocket",
        hidden = false,
        order = "z"
    }
    generator_util.add_groups(custom_items["custom-silo-rocket"], "intermediate-products", "intermediate-product")


    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto = (type == "entity") and custom_items[item_name] or
                prototypes[type][item_name]  ---@type LuaItemPrototype | LuaFluidPrototype

            local item = {
                name = item_name,
                localised_name = proto.localised_name,
                type = type,
                hidden = (not rocket_parts[item_name]) and proto.hidden,
                stack_size = (type == "item") and proto.stack_size or nil,
                weight = (type == "item") and proto.weight or nil,
                ingredient_only = not item_details.is_product,
                order = proto.order
            }

            if type == "entity" then
                item.sprite = proto.sprite
                item.group = proto.group
                item.subgroup = proto.subgroup
                item.tooltip = proto.localised_name
                item.fixed_unit = proto.fixed_unit or nil
            else
                item.sprite = (type .. "/" .. proto.name)
                item.group = generator_util.generate_group_table(proto.group)
                item.subgroup = generator_util.generate_group_table(proto.subgroup)
            end

            insert_prototype(items, item, item.type)
        end
    end

    return items
end


---@class FPFuelPrototype: FPPrototypeWithCategory
---@field data_type "fuels"
---@field type "item" | "fluid"
---@field category string | "fluid-fuel"
---@field combined_category string
---@field elem_type ElemType
---@field fuel_value float
---@field stack_size uint?
---@field weight double?
---@field emissions_multiplier double
---@field burnt_result string?

-- Generates a table containing all fuels that can be used in a burner
---@return NamedPrototypesWithCategory<FPFuelPrototype>
function generator.fuels.generate()
    local fuels = {}  ---@type NamedPrototypesWithCategory<FPFuelPrototype>

    local fuel_filter = {{filter="fuel-value", comparison=">", value=0},
        {filter="fuel-value", comparison="<", value=1e+21, mode="and"}--[[ ,
        {filter="hidden", invert=true, mode="and"} ]]}

    -- Build solid fuels - to be combined into categories afterwards
    local item_list = storage.prototypes.items["item"].members  ---@type NamedPrototypesWithCategory<FPItemPrototype>
    local fuel_categories = {}  -- temporary list to be combined later
    for _, proto in pairs(prototypes.get_item_filtered(fuel_filter)) do
        -- Only use fuels that were actually detected/accepted to be items
        if item_list[proto.name] then
            local fuel = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "item/" .. proto.name,
                type = "item",
                elem_type = "item",
                category = proto.fuel_category,
                fuel_value = proto.fuel_value,
                stack_size = proto.stack_size,
                weight = proto.weight,
                emissions_multiplier = proto.fuel_emissions_multiplier,
                burnt_result = (proto.burnt_result) and proto.burnt_result.name or nil
            }
            fuel_categories[fuel.category] = fuel_categories[fuel.category] or {}
            table.insert(fuel_categories[fuel.category], fuel)
        end
    end

    -- Create category for each combination of fuel used by machines
    -- Also filters out any fuels that aren't used by any actual machine
    for _, machine_category in pairs(storage.prototypes.machines) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.burner then
                local combined_category = machine_proto.burner.combined_category
                for fuel_category, _ in pairs(machine_proto.burner.categories) do
                    for _, fuel in pairs(fuel_categories[fuel_category]) do
                        fuel.combined_category = combined_category
                        insert_prototype(fuels, fuel, combined_category)
                    end
                end
            end
        end
    end

    -- Add liquid fuels - they are a category of their own always
    local fluid_list = storage.prototypes.items["fluid"].members  ---@type NamedPrototypesWithCategory<FPItemPrototype>
    for _, proto in pairs(prototypes.get_fluid_filtered(fuel_filter)) do
        -- Only use fuels that have actually been detected/accepted as fluids
        if fluid_list[proto.name] then
            local fuel = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "fluid/" .. proto.name,
                type = "fluid",
                elem_type = "fluid",
                category = "fluid-fuel",
                combined_category = "fluid-fuel",
                fuel_value = proto.fuel_value,
                stack_size = nil,
                weight = nil,
                emissions_multiplier = proto.emissions_multiplier,
                burnt_result = nil
            }
            insert_prototype(fuels, fuel, fuel.combined_category)
        end
    end

    return fuels
end


---@class FPBeltPrototype: FPPrototype
---@field data_type "belts"
---@field elem_type ElemType
---@field rich_text string
---@field throughput double

-- Generates a table containing all available transport belts
---@return NamedPrototypes<FPBeltPrototype>
function generator.belts.generate()
    local belts = {} ---@type NamedPrototypes<FPBeltPrototype>

    local belt_filter = {{filter="type", type="transport-belt"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(belt_filter)) do
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite ~= nil then
            local belt = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                throughput = proto.belt_speed * 480
            }
            insert_prototype(belts, belt, nil)
        end
    end

    return belts
end

---@param a FPBeltPrototype
---@param b FPBeltPrototype
---@return boolean
function generator.belts.sorting_function(a, b)
    if a.throughput < b.throughput then return true
    elseif a.throughput > b.throughput then return false end
    return false
end


---@class FPWagonPrototype: FPPrototypeWithCategory
---@field data_type "wagons"
---@field category "cargo-wagon" | "fluid-wagon"
---@field elem_type ElemType
---@field rich_text string
---@field storage number

-- Generates a table containing all available cargo and fluid wagons
---@return NamedPrototypesWithCategory<FPWagonPrototype>
function generator.wagons.generate()
    local wagons = {}  ---@type NamedPrototypesWithCategory<FPWagonPrototype>

    -- Add cargo wagons
    local cargo_wagon_filter = {{filter="type", type="cargo-wagon"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(cargo_wagon_filter)) do
        local inventory_size = proto.get_inventory_size(defines.inventory.cargo_wagon)
        if inventory_size > 0 then
            local wagon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = generator_util.determine_entity_sprite(proto),
                category = "cargo-wagon",
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                storage = inventory_size
            }
            insert_prototype(wagons, wagon, wagon.category)
        end
    end

    -- Add fluid wagons
    local fluid_wagon_filter = {{filter="type", type="fluid-wagon"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(fluid_wagon_filter)) do
        if proto.fluid_capacity > 0 then
            local wagon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = generator_util.determine_entity_sprite(proto),
                category = "fluid-wagon",
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                storage = proto.fluid_capacity
            }
            insert_prototype(wagons, wagon, wagon.category)
        end
    end

    return wagons
end

---@param a FPWagonPrototype
---@param b FPWagonPrototype
---@return boolean
function generator.wagons.sorting_function(a, b)
    if a.storage < b.storage then return true
    elseif a.storage > b.storage then return false end
    return false
end


---@class FPModulePrototype: FPPrototypeWithCategory
---@field data_type "modules"
---@field category string
---@field tier uint
---@field effects ModuleEffects

-- Generates a table containing all available modules
---@return NamedPrototypesWithCategory<FPModulePrototype>
function generator.modules.generate()
    local modules = {}  ---@type NamedPrototypesWithCategory<FPModulePrototype>

    local module_filter = {{filter="type", type="module"}--[[ , {filter="hidden", invert=true, mode="and"} ]]}
    for _, proto in pairs(prototypes.get_item_filtered(module_filter)) do
        local sprite = "item/" .. proto.name
        if game.is_valid_sprite_path(sprite) then
            local module = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = proto.category,
                tier = proto.tier,
                effects = proto.module_effects or {}
            }
            if module.effects["quality"] then  -- fix base game weirdness
                module.effects["quality"] = module.effects["quality"] / 10
            end
            insert_prototype(modules, module, module.category)
        end
    end

    return modules
end


---@class FPBeaconPrototype: FPPrototype
---@field data_type "beacons"
---@field category "beacon"
---@field elem_type ElemType
---@field built_by_item FPItemPrototype
---@field allowed_effects AllowedEffects
---@field module_limit uint
---@field effectivity double
---@field quality_bonus double
---@field profile double[]
---@field energy_usage double

-- Generates a table containing all available beacons
---@return NamedPrototypes<FPBeaconPrototype>
function generator.beacons.generate()
    local beacons = {}  ---@type NamedPrototypes<FPBeaconPrototype>

    ---@type NamedPrototypesWithCategory<FPItemPrototype>
    local item_prototypes = storage.prototypes.items["item"].members

    local beacon_filter = {{filter="type", type="beacon"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(beacon_filter)) do
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite ~= nil and proto.module_inventory_size > 0 and proto.distribution_effectivity > 0 then
            -- Beacons can refer to the actual item prototype right away because they are built after items are
            local items_to_place_this = proto.items_to_place_this
            local built_by_item = (items_to_place_this) and item_prototypes[items_to_place_this[1].name] or nil

            local beacon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "beacon",  -- custom category to be similar to machines
                elem_type = "entity",
                built_by_item = built_by_item,
                allowed_effects = proto.allowed_effects,
                module_limit = proto.module_inventory_size,
                effectivity = proto.distribution_effectivity,
                quality_bonus = proto.distribution_effectivity_bonus_per_quality_level,
                profile = proto.profile,
                energy_usage = proto.energy_usage or proto.get_max_energy_usage() or 0
            }
            insert_prototype(beacons, beacon, nil)
        end
    end

    return beacons
end


-- Doesn't need to be a lasting part of the generator as it's only used for LocationPrototypes generation
---@return LuaSurfacePropertyPrototype[]
local function generate_surface_properties()
    local properties = {}

    ---@param a LuaSurfacePropertyPrototype
    ---@param b LuaSurfacePropertyPrototype
    ---@return boolean
    local function property_sorting_function(a, b)
        if a.order < b.order then return true
        elseif a.order > b.order then return false end
        return false
    end

    for _, proto in pairs(prototypes.surface_property) do
        table.insert(properties, {
            name = proto.name,
            order = proto.order,
            localised_name = proto.localised_name,
            localised_unit = proto.localised_unit,
            default_value = proto.default_value,
            is_time = proto.is_time
        })
    end

    table.sort(properties, property_sorting_function)
    return properties
end

---@class FPLocationPrototype: FPPrototype
---@field data_type "locations"
---@field tooltip LocalisedString
---@field surface_properties SurfaceProperties?
---@field pollutant_type string?

---@alias SurfaceProperties { string: double }

-- Generates a table containing all 'places' with surface_conditions, like planets and platforms
---@return NamedPrototypes<FPLocationPrototype>
function generator.locations.generate()
    local locations = {}  ---@type NamedPrototypes<FPLocationPrototype>

    local property_prototypes = generate_surface_properties()

    ---@param proto LuaSpaceLocationPrototype | LuaSurfacePrototype
    ---@param type_ string
    ---@return FPLocationPrototype? location_proto
    local function build_location(proto, type_)
        local sprite = type_ .. "/" .. proto.name
        if not proto.hidden and not game.is_valid_sprite_path(sprite) then return nil end
        if not proto.surface_properties then return nil end

        local surface_properties, tooltip = {}, {"", {"fp.tt_title", proto.localised_name}, "\n"}
        for _, property_proto in pairs(property_prototypes) do
            local value = proto.surface_properties[property_proto.name] or property_proto.default_value
            surface_properties[property_proto.name] = value

            local value_and_unit = {"", value, property_proto.localised_unit}  ---@type LocalisedString
            if property_proto.is_time then value_and_unit = util.format.time(value) end
            table.insert(tooltip, {"fp.surface_property", property_proto.localised_name, value_and_unit})
        end

        return {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = sprite,
            tooltip = tooltip,
            surface_properties = surface_properties,
            pollutant_type = (type_ == "space-location" and proto.pollutant_type) and proto.pollutant_type.name or nil
        }
    end

    for _, proto in pairs(prototypes.space_location) do
        if proto.name ~= "space-location-unknown" then  -- Shouldn't this be hidden by the game?
            local location = build_location(proto, "space-location")
            if location then insert_prototype(locations, location, nil) end
        end
    end

    for _, proto in pairs(prototypes.surface) do
        local location = build_location(proto, "surface")
        if location then insert_prototype(locations, location, nil) end
    end

    return locations
end

---@class FPQualityPrototype: FPPrototype
---@field data_type "qualities"
---@field rich_text LocalisedString
---@field level uint
---@field always_show boolean
---@field multiplier double
---@field beacon_power_usage_multiplier double
---@field mining_drill_resource_drain_multiplier double

---@return NamedPrototypes<FPQualityPrototype>
function generator.qualities.generate()
    local qualities = {}  ---@type NamedPrototypes<FPQualityPrototype>

    for _, proto in pairs(prototypes.quality) do
        if proto.name ~= "quality-unknown" then  -- Shouldn't this be hidden by the game?
            local sprite = "quality/" .. proto.name
            if game.is_valid_sprite_path(sprite) then
                local quality = {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = sprite,
                    rich_text = {"", "[img=" .. sprite .. "]", proto.localised_name},
                    level = proto.level,
                    always_show = proto.draw_sprite_by_default,
                    multiplier = 1 + (proto.level * 0.3),
                    beacon_power_usage_multiplier = proto.beacon_power_usage_multiplier,
                    mining_drill_resource_drain_multiplier = proto.mining_drill_resource_drain_multiplier
                }
                insert_prototype(qualities, quality, nil)
            end
        end
    end

    return qualities
end

---@param a FPQualityPrototype
---@param b FPQualityPrototype
---@return boolean
function generator.qualities.sorting_function(a, b)
    if a.level < b.level then return true
    elseif a.level > b.level then return false end
    return false
end


return generator

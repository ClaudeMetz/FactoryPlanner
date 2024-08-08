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
---@field resource_drain_rate number?

---@class FluidChannels
---@field input integer
---@field output integer

---@class MachineBurner
---@field effectivity double
---@field categories { [string]: boolean }

---@alias EmissionsMap { [string]: double }

-- Generates a table containing all machines for all categories
---@return NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.generate()
    local machines = {}  ---@type NamedPrototypesWithCategory<FPMachinePrototype>

    ---@param category string
    ---@param proto LuaEntityPrototype
    ---@param quality_category ("assembling-machine" | "mining-drill")?
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
            burner = {effectivity = burner_prototype.effectivity, categories = burner_prototype.fuel_categories}

        -- Only supports fluid energy that burns_fluid for now, as it works the same way as solid burners
        -- Also doesn't respect scale_fluid_usage and fluid_usage_per_tick for now, let the reports come
        elseif fluid_burner_prototype then
            emissions_per_joule = fluid_burner_prototype.emissions_per_joule

            if fluid_burner_prototype.burns_fluid and not fluid_burner_prototype.fluid_box.filter then
                energy_type = "burner"
                burner = {effectivity = fluid_burner_prototype.effectivity, categories = {["fluid-fuel"] = true}}

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
        }
        generator_util.check_machine_effects(machine)

        return machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if --[[ not proto.hidden and ]] proto.crafting_categories and proto.energy_usage ~= nil
                and not generator_util.is_irrelevant_machine(proto) then
            for category, _ in pairs(proto.crafting_categories) do
                local machine = generate_category_entry(category, proto, "assembling-machine")
                if machine then insert_prototype(machines, machine, machine.category) end
            end

        -- Add mining machines
        elseif proto.resource_categories then
            if --[[ not proto.hidden and ]] proto.type ~= "character" then
                for category, enabled in pairs(proto.resource_categories) do
                    -- Only supports solid mining recipes for now (no oil, etc.)
                    if enabled and category ~= "basic-fluid" then
                        local machine = generate_category_entry(category, proto, "mining-drill")
                        if machine then
                            machine.speed = proto.mining_speed
                            machine.resource_drain_rate = proto.resource_drain_rate_percent / 100
                            insert_prototype(machines, machine, category)
                        end
                    end
                end
            end

        elseif proto.type == "offshore-pump" then
            local machine = generate_category_entry(proto.type, proto, nil)
            if machine then
                machine.speed = proto.pumping_speed
                insert_prototype(machines, machine, proto.type)
            end

        elseif proto.type == "agricultural-tower" then
            local machine = generate_category_entry(proto.type, proto, nil)
            if machine then
                --[[ local growth_area_width = (proto.growth_grid_tile_size * 2) + 1
                local available_tiles = growth_area_width * growth_area_width - 1 ]]
                -- deal with energy_usage, crane_energy_usage
                machine.speed = 48--available_tiles
                machine.energy_usage = 0  -- implemented later
                insert_prototype(machines, machine, proto.type)
            end
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

    return machines
end

---@param machines NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.second_pass(machines)
    -- Go over all recipes to find unused categories
    local used_category_names = {}  ---@type { [string]: boolean }
    for _, recipe_proto in pairs(global.prototypes.recipes) do
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
                    if global.prototypes.fuels[fuel_category] then category_found = true; break end
                end
                if not category_found then remove_prototype(machines, machine_proto.name, machine_category.name) end
            end
        end

        -- If the category ends up empty because of this, make sure to remove it
        if not next(machine_category.members) then machines[machine_category.name] = nil end
    end


    -- Replace built_by_item names with prototype references
    local item_prototypes = global.prototypes.items["item"].members  ---@type { [string]: FPItemPrototype }
    for _, machine_category in pairs(machines) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.built_by_item then
                machine_proto.built_by_item = item_prototypes[machine_proto.built_by_item]
            end
        end
    end
end

---@param a FPMachinePrototype
---@param b FPMachinePrototype
---@return boolean
function generator.machines.sorting_function(a, b)
    if a.speed < b.speed then return true
    elseif a.speed > b.speed then return false
    elseif a.module_limit < b.module_limit then return true
    elseif a.module_limit > b.module_limit then return false
    elseif a.energy_usage < b.energy_usage then return true
    elseif a.energy_usage > b.energy_usage then return false end
    return false
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
        return {
            custom = true,
            enabled_from_the_start = true,
            hidden = false,
            group = {name="intermediate-products", order="c", valid=true,
                localised_name={"item-group-name.intermediate-products"}},
            maximum_productivity = math.huge,
            type_counts = {},
            enabling_technologies = nil,
            emissions_multiplier = 1
        }
    end


    -- Determine researchable recipes
    local researchable_recipes = {}  ---@type { [string]: string[] }
    local tech_filter = {{filter="hidden", invert=true}, {filter="has-effects", mode="and"}}
    for _, tech_proto in pairs(game.get_filtered_technology_prototypes(tech_filter)) do
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
    for _, item_proto in pairs(game.item_prototypes) do
        if item_proto.plant_result then
            plant_seed_map[item_proto.plant_result.name] = item_proto.name
        end
    end

    -- Add all standard recipes
    local recipe_filter = {{filter="energy", comparison=">", value=0},
        {filter="energy", comparison="<", value=1e+21, mode="and"}}
    for recipe_name, proto in pairs(game.get_filtered_recipe_prototypes(recipe_filter)) do
        local machine_category = global.prototypes.machines[proto.category]  ---@type { [string]: FPMachinePrototype }
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

    for _, proto in pairs(game.entity_prototypes) do
        -- Add all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end

            local produces_solid = false
            for _, product in pairs(products) do
                if product.type == "item" then produces_solid = true; break end
                product.ignored_by_productivity = product.amount
            end
            if not produces_solid then goto incompatible_proto end

            if produces_solid then
                local recipe = custom_recipe()
                recipe.name = "impostor-" .. proto.name
                recipe.localised_name = {"", proto.localised_name, " ", {"fp.mining_recipe"}}
                recipe.sprite = products[1].type .. "/" .. products[1].name
                recipe.order = proto.order
                recipe.subgroup = {name="mining", order="y", valid=true}
                recipe.category = proto.resource_category
                -- Set energy to mining time so the forumla for the machine_count works out
                recipe.energy = proto.mineable_properties.mining_time

                local ingredients = {{type="entity", name="custom-" .. proto.name, amount=1}}

                -- Add mining fluid, if required
                if proto.mineable_properties.required_fluid then
                    table.insert(ingredients, {
                        type = "fluid",
                        name = proto.mineable_properties.required_fluid,
                        -- fluid_amount is given for a 'set' of mining ops, with a set being 10 ore
                        amount = proto.mineable_properties.fluid_amount / 10
                    })
                end

                generator_util.format_recipe(recipe, products, products[1], ingredients)

                insert_prototype(recipes, recipe, nil)

            --else
                -- crude-oil etc goes here
            end

            ::incompatible_proto::

        -- Add agricultural tower recipes
        elseif proto.type == "plant" then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end
            local seed_name = plant_seed_map[proto.name]
            if not seed_name then goto incompatible_proto end

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.localised_name = {"", proto.localised_name, " ", {"fp.planting_recipe"}}
            recipe.sprite = products[1].type .. "/" .. products[1].name
            recipe.order = proto.order
            recipe.subgroup = {name="planting", order="z", valid=true}
            recipe.category = "agricultural-tower"
            recipe.energy = proto.growth_ticks / 60

            -- Deal with proto.harvest_emissions + proto.emissions_per_second somehow, probably on machine?

            local ingredients = {{type="item", name=seed_name, amount=1}}
            generator_util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)

            ::incompatible_proto::

        -- Add convenience recipes to build whole rockets instead of parts
        elseif proto.type == "rocket-silo" then
            local parts_recipe = recipes[proto.fixed_recipe]

            local rocket_recipe = ftable.deep_copy(parts_recipe)
            rocket_recipe.name = "impostor-" .. proto.name .. "-rocket"
            rocket_recipe.localised_name = {"", proto.localised_name, " ", {"fp.launch"}}
            rocket_recipe.sprite = "fp_silo_rocket"
            rocket_recipe.order = rocket_recipe.order .. "-" .. proto.order
            rocket_recipe.custom = true

            generator_util.multiply_recipe(rocket_recipe, proto.rocket_parts_required)
            rocket_recipe.products = {{type="entity", name="custom-silo-rocket", amount=1}}

            insert_prototype(recipes, rocket_recipe, nil)
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
                        recipe.subgroup = {name="fluids", order="z", valid=true}
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

    -- Add offshore pump recipes
    local pumped_fluids = {}
    for _, proto in pairs(game.tile_prototypes) do
        if proto.fluid and not pumped_fluids[proto.fluid.name] then
            pumped_fluids[proto.fluid.name] = true

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            recipe.localised_name = {"", proto.fluid.localised_name, " ", {"fp.pumping_recipe"}}
            recipe.sprite = "fluid/" .. proto.fluid.name
            recipe.order = proto.order
            recipe.subgroup = {name="fluids", order="z", valid=true}
            recipe.category = "offshore-pump"
            recipe.energy = 1

            local products = {{type="fluid", name=proto.fluid.name, amount=60}}
            generator_util.format_recipe(recipe, products, products[1], {})

            insert_prototype(recipes, recipe, nil)
        end
    end

    -- Add a general steam recipe that works with every boiler
    --[[ if game["fluid_prototypes"]["steam"] then  -- make sure the steam prototype exists
        local recipe = custom_recipe()
        recipe.name = "fp-general-steam"
        recipe.localised_name = {"fluid-name.steam"}
        recipe.sprite = "fluid/steam"
        recipe.category = "general-steam"
        recipe.order = "z-0"
        recipe.subgroup = {name="fluids", order="z", valid=true}
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
    local machines = global.prototypes.machines
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
---@field ingredient_only boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup
---@field tooltip LocalisedString?

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
    for _, recipe_proto in pairs(global.prototypes.recipes) do
        for _, product in pairs(recipe_proto.products) do
            add_item(relevant_items, {proto=product, is_product=true})
        end
        for _, ingredient in pairs(recipe_proto.ingredients) do
            add_item(relevant_items, {proto=ingredient, is_product=false})
        end
    end


    local custom_items, rocket_parts = {}, {}
    -- Build custom items, representing in-world entities mostly
    for _, proto in pairs(game.entity_prototypes) do
        -- Add all mining deposits. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category then
            local name = "custom-" .. proto.name
            custom_items[name] = {
                name = name,
                localised_name = {"", proto.localised_name, " ", {"fp.deposit"}},
                sprite = "entity/" .. proto.name,
                hidden = true,
                order = proto.order,
                group = proto.group,
                subgroup = proto.subgroup
            }

        -- Mark rocket silo part items here so they can be marked as non-hidden
        elseif proto.type == "rocket-silo" then
            local parts_recipe = game.recipe_prototypes[proto.fixed_recipe]
            rocket_parts[parts_recipe.main_product.name] = true
        end
    end

    -- Only need one rocket item for all silos/recipes
    custom_items["custom-silo-rocket"] = {
        name = "custom-silo-rocket",
        localised_name = {"", {"entity-name.rocket"}, " ", {"fp.launch"}},
        sprite = "fp_silo_rocket",
        hidden = false,
        order = "z",
        group = {name="intermediate-products", order="c", valid=true,
            localised_name={"item-group-name.intermediate-products"}},
        subgroup = {name="intermediate-product", order="g", valid=true,
            localised_name={"item-subgroup-name.intermediate-product"}},
    }


    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto = (type == "entity") and custom_items[item_name] or
                game[type .. "_prototypes"][item_name]  ---@type LuaItemPrototype | LuaFluidPrototype
            local sprite = (type == "entity") and proto.sprite or (type .. "/" .. proto.name)
            local tooltip = (type == "entity") and proto.localised_name or nil

            local item = {
                name = item_name,
                localised_name = proto.localised_name,
                sprite = sprite,
                type = type,
                hidden = (not rocket_parts[item_name]) and proto.hidden,
                stack_size = (type == "item") and proto.stack_size or nil,
                ingredient_only = not item_details.is_product,
                order = proto.order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup),
                tooltip = tooltip
            }

            insert_prototype(items, item, item.type)
        end
    end

    return items
end


---@class FPFuelPrototype: FPPrototypeWithCategory
---@field data_type "fuels"
---@field type "item" | "fluid"
---@field category string | "fluid-fuel"
---@field elem_type ElemType
---@field fuel_value float
---@field stack_size uint?
---@field emissions_multiplier double

-- Generates a table containing all fuels that can be used in a burner
---@return NamedPrototypesWithCategory<FPFuelPrototype>
function generator.fuels.generate()
    local fuels = {}  ---@type NamedPrototypesWithCategory<FPFuelPrototype>

    -- Determine all the fuel categories that the machine prototypes use
    local used_fuel_categories = {}  ---@type { [string]: boolean}
    for _, machine_category in pairs(global.prototypes.machines) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.burner then
                for category_name, _ in pairs(machine_proto.burner.categories) do
                    used_fuel_categories[category_name] = true
                end
            end
        end
    end

    local fuel_filter = {{filter="fuel-value", comparison=">", value=0},
        {filter="fuel-value", comparison="<", value=1e+21, mode="and"}--[[ ,
        {filter="hidden", invert=true, mode="and"} ]]}

    -- Add solid fuels
    local item_list = global.prototypes.items["item"].members  ---@type NamedPrototypesWithCategory<FPItemPrototype>
    for _, proto in pairs(game.get_filtered_item_prototypes(fuel_filter)) do
        -- Only use fuels that were actually detected/accepted to be items and find use in at least one machine
        if item_list[proto.name] and used_fuel_categories[proto.fuel_category] ~= nil then
            local fuel = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "item/" .. proto.name,
                type = "item",
                elem_type = "item",
                category = proto.fuel_category,
                fuel_value = proto.fuel_value,
                stack_size = proto.stack_size,
                emissions_multiplier = proto.fuel_emissions_multiplier
            }
            insert_prototype(fuels, fuel, fuel.category)
        end
    end

    -- Add liquid fuels
    local fluid_list = global.prototypes.items["fluid"].members  ---@type NamedPrototypesWithCategory<FPItemPrototype>
    for _, proto in pairs(game.get_filtered_fluid_prototypes(fuel_filter)) do
        -- Only use fuels that have actually been detected/accepted as fluids
        if fluid_list[proto.name] then
            local fuel = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "fluid/" .. proto.name,
                type = "fluid",
                elem_type = "fluid",
                category = "fluid-fuel",
                fuel_value = proto.fuel_value,
                stack_size = nil,
                emissions_multiplier = proto.emissions_multiplier
            }
            insert_prototype(fuels, fuel, fuel.category)
        end
    end

    return fuels
end

---@param a FPFuelPrototype
---@param b FPFuelPrototype
---@return boolean
function generator.fuels.sorting_function(a, b)
    if a.fuel_value < b.fuel_value then return true
    elseif a.fuel_value > b.fuel_value then return false
    elseif a.emissions_multiplier < b.emissions_multiplier then return true
    elseif a.emissions_multiplier > b.emissions_multiplier then return false end
    return false
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
    for _, proto in pairs(game.get_filtered_entity_prototypes(belt_filter)) do
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
    for _, proto in pairs(game.get_filtered_entity_prototypes(cargo_wagon_filter)) do
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
    for _, proto in pairs(game.get_filtered_entity_prototypes(fluid_wagon_filter)) do
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
    for _, proto in pairs(game.get_filtered_item_prototypes(module_filter)) do
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
    local item_prototypes = global.prototypes.items["item"].members

    local beacon_filter = {{filter="type", type="beacon"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(beacon_filter)) do
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

---@param a FPBeaconPrototype
---@param b FPBeaconPrototype
---@return boolean
function generator.beacons.sorting_function(a, b)
    if a.module_limit < b.module_limit then return true
    elseif a.module_limit > b.module_limit then return false
    elseif a.effectivity < b.effectivity then return true
    elseif a.effectivity > b.effectivity then return false
    elseif a.energy_usage < b.energy_usage then return true
    elseif a.energy_usage > b.energy_usage then return false end
    return false
end


-- Doesn't need to be a lasting part of the generator as it's only used for LocationPrototypes generation
---@return { name: string, order: string, localised_name: LocalisedString, localised_unit: LocalisedString, default_value: double, is_time: boolean }[]
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

    for _, proto in pairs(game.surface_property_prototypes) do
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
---@field surface_properties { string: double }?

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
        if --[[ not proto.hidden and ]] not game.is_valid_sprite_path(sprite) then return nil end

        local surface_properties, tooltip = nil, {"", {"fp.tt_title", proto.localised_name}}

        if proto.surface_properties then
            surface_properties = {}
            table.insert(tooltip, "\n")

            for _, property_proto in pairs(property_prototypes) do
                local value = proto.surface_properties[property_proto.name] or property_proto.default_value
                surface_properties[property_proto.name] = value

                local value_and_unit = {"", value, property_proto.localised_unit}  ---@type LocalisedString
                if property_proto.is_time then value_and_unit = util.format.format_time(value) end
                table.insert(tooltip, {"fp.surface_property", property_proto.localised_name, value_and_unit})
            end
        end

        return {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = sprite,
            tooltip = tooltip,
            surface_properties = surface_properties
        }
    end

    for _, proto in pairs(game.space_location_prototypes) do
        if proto.name ~= "space-location-unknown" then  -- only until hidden API is available
            local location = build_location(proto, "space-location")
            if location then insert_prototype(locations, location, nil) end
        end
    end

    --[[ for _, proto in pairs(game.surface_prototypes) do
        local location = build_location(proto, "surface")
        if location then insert_prototype(locations, location, nil) end
    end ]]

    return locations
end

---@class FPQualityPrototype: FPPrototype
---@field data_type "qualities"
---@field level uint
---@field multiplier double

---@return NamedPrototypes<FPQualityPrototype>
function generator.qualities.generate()
    local qualities = {}  ---@type NamedPrototypes<FPQualityPrototype>

    for _, proto in pairs(game.quality_prototypes) do
        if proto.name ~= "quality-unknown" then  -- only until hidden API is available, maybe
            local sprite = "quality/" .. proto.name
            if game.is_valid_sprite_path(sprite) then
                local quality = {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = sprite,
                    --color = proto.color, -- useful for tooltips, probably formatted into rich text
                    level = proto.level,
                    multiplier = 1 + (proto.level * 0.3)
                    -- Also has these two, we'll see how they work
                    --beacon_power_usage_multiplier
                    --mining_drill_resource_drain_multiplier
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

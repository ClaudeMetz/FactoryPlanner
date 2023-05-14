require("data.handlers.generator_util")

generator = {}

---@class FPRecipePrototype
---@field name string
---@field category string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field energy double
---@field emissions_multiplier double
---@field ingredients Ingredient[]
---@field products Product[]
---@field main_product Product?
---@field type_count any
---@field recycling boolean
---@field barreling boolean
---@field enabling_technologies string[]
---@field use_limitations boolean
---@field custom boolean
---@field enabled_from_the_start boolean
---@field hidden boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup

-- Returns all standard recipes + custom mining, steam and rocket recipes
function generator.all_recipes()
    generator_util.data_structure.init("simple", "recipes")

    local function custom_recipe()
        return {
            custom = true,
            enabled_from_the_start = true,
            hidden = false,
            group = {name="intermediate-products", order="c", valid=true,
                localised_name={"item-group-name.intermediate-products"}},
            type_counts = {},
            enabling_technologies = nil,
            use_limitations = false,
            emissions_multiplier = 1
        }
    end


    -- Determine researchable recipes
    local researchable_recipes = {}
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

    -- Add all standard recipes
    local recipe_filter = {{filter="energy", comparison=">", value=0},
        {filter="energy", comparison="<", value=1e+21, mode="and"}}
    for recipe_name, proto in pairs(game.get_filtered_recipe_prototypes(recipe_filter)) do
        local category_id = NEW.all_machines.map[proto.category]
        -- Avoid any recipes that have no machine to produce them, or are irrelevant
        if category_id ~= nil and not generator_util.is_irrelevant_recipe(proto) then
            local recipe = {
                name = proto.name,
                category = proto.category,
                localised_name = proto.localised_name,
                sprite = "recipe/" .. proto.name,
                energy = proto.energy,
                emissions_multiplier = proto.emissions_multiplier,
                ingredients = proto.ingredients,
                products = proto.products,
                main_product = proto.main_product,
                type_counts = {},  -- filled out by format_* below
                recycling = generator_util.is_recycling_recipe(proto),
                barreling = generator_util.is_compacting_recipe(proto),
                enabling_technologies = researchable_recipes[recipe_name],  -- can be nil
                use_limitations = true,
                custom = false,
                enabled_from_the_start = proto.enabled,
                hidden = proto.hidden,
                order = proto.order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup)
            }

            generator_util.format_recipe_products_and_ingredients(recipe)
            generator_util.data_structure.insert(recipe)
        end
    end


    -- Determine all the items that can be inserted usefully into a rocket silo
    local launch_products_filter = {{filter="has-rocket-launch-products"}}
    local rocket_silo_inputs = {}
    for _, item in pairs(game.get_filtered_item_prototypes(launch_products_filter)) do
        if next(item.rocket_launch_products) then
            table.insert(rocket_silo_inputs, item)
        end
    end

    -- Localize them here so they don't have to be recreated over and over
    local item_prototypes, recipe_prototypes = game.item_prototypes, game.recipe_prototypes

    -- Add mining recipes
    for _, proto in pairs(game.entity_prototypes) do
        -- Add all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end

            local produces_solid = false
            for _, product in pairs(products) do  -- detects all solid mining recipes
                if product.type == "item" then produces_solid = true; break end
            end
            if not produces_solid then goto incompatible_proto end

            if produces_solid then
                local recipe = custom_recipe()
                recipe.name = "impostor-" .. proto.name
                recipe.localised_name = proto.localised_name
                recipe.sprite = products[1].type .. "/" .. products[1].name
                recipe.order = proto.order
                recipe.subgroup = {name="mining", order="y", valid=true}
                recipe.category = proto.resource_category
                recipe.mining = true
                -- Set energy to mining time so the forumla for the machine_count works out
                recipe.energy = proto.mineable_properties.mining_time
                recipe.ingredients = {{type="entity", name=proto.name, amount=1}}
                recipe.products = products
                recipe.main_product = recipe.products[1]

                -- Add mining fluid, if required
                if proto.mineable_properties.required_fluid then
                    table.insert(recipe.ingredients, {
                        type = "fluid",
                        name = proto.mineable_properties.required_fluid,
                        -- fluid_amount is given for a 'set' of mining ops, with a set being 10 ore
                        amount = proto.mineable_properties.fluid_amount / 10
                    })
                end

                generator_util.format_recipe_products_and_ingredients(recipe)
                generator_util.add_recipe_tooltip(recipe)
                generator_util.data_structure.insert(recipe)

            --else
                -- crude-oil and angels-natural-gas go here (not interested atm)
            end

            ::incompatible_proto::

        -- Add offshore-pump fluid recipes
        elseif proto.fluid then
            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            recipe.localised_name = proto.fluid.localised_name
            recipe.sprite = "fluid/" .. proto.fluid.name
            recipe.order = proto.order
            recipe.subgroup = {name="fluids", order="z", valid=true}
            recipe.category = proto.name  -- use proto name so every pump has it's own category
            recipe.energy = 1
            recipe.ingredients = {}
            recipe.products = {{type="fluid", name=proto.fluid.name, amount=(proto.pumping_speed * 60)}}
            recipe.main_product = recipe.products[1]

            generator_util.format_recipe_products_and_ingredients(recipe)
            generator_util.add_recipe_tooltip(recipe)
            generator_util.data_structure.insert(recipe)

        -- Detect all the implicit rocket silo recipes
        elseif proto.rocket_parts_required ~= nil then
            local fixed_recipe = recipe_prototypes[proto.fixed_recipe]
            if fixed_recipe ~= nil then
                -- Add recipe for all 'launchable' items
                for _, silo_input in pairs(rocket_silo_inputs) do
                    local silo_product = table_size(silo_input.rocket_launch_products) > 1
                        and item_prototypes[silo_input.rocket_launch_products[1].name] or silo_input

                    local recipe = custom_recipe()
                    recipe.name = "impostor-silo-" .. proto.name .. "-item-" .. silo_input.name
                    recipe.localised_name = silo_product.localised_name
                    recipe.sprite = "item/" .. silo_product.name
                    recipe.category = next(proto.crafting_categories, nil)  -- hopefully this stays working
                    recipe.energy = fixed_recipe.energy * proto.rocket_parts_required
                    recipe.subgroup = {name="science-pack", order="g", valid=true}
                    recipe.order = "x-silo-" .. proto.order .. "-" .. silo_input.order

                    recipe.ingredients = fixed_recipe.ingredients
                    for _, ingredient in pairs(recipe.ingredients) do
                        ingredient.amount = ingredient.amount * proto.rocket_parts_required
                    end
                    table.insert(recipe.ingredients, {type="item", name=silo_input.name,
                        amount=1, ignore_productivity=true})
                    recipe.products = silo_input.rocket_launch_products
                    recipe.main_product = recipe.products[1]

                    generator_util.format_recipe_products_and_ingredients(recipe)
                    generator_util.add_recipe_tooltip(recipe)
                    generator_util.data_structure.insert(recipe)
                end

                -- Modify recipe for all rocket parts so they represent a full launch
                -- This is needed so the launch sequence times can be incorporated correctly
                local rocket_part_recipe = generator_util.data_structure.get_prototype(fixed_recipe.name, nil)
                if rocket_part_recipe then
                    generator_util.multiply_recipe(rocket_part_recipe, proto.rocket_parts_required)
                end
            end
        end

        -- Add a recipe for producing steam from a boiler
        local existing_recipe_names = {}
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
                        recipe.ingredients = {{type="fluid", name="water", amount=60}}
                        recipe.products = {{type="fluid", name="steam", amount=60, temperature=temperature}}
                        recipe.main_product = recipe.products[1]

                        generator_util.format_recipe_products_and_ingredients(recipe)
                        generator_util.add_recipe_tooltip(recipe)
                        generator_util.data_structure.insert(recipe)
                    end
                end
            end
        end
    end

    -- Add a general steam recipe that works with every boiler
    if game["fluid_prototypes"]["steam"] then  -- make sure the steam prototype exists
        local steam_recipe = custom_recipe()
        steam_recipe.name = "fp-general-steam"
        steam_recipe.localised_name = {"fluid-name.steam"}
        steam_recipe.sprite = "fluid/steam"
        steam_recipe.category = "general-steam"
        steam_recipe.order = "z-0"
        steam_recipe.subgroup = {name="fluids", order="z", valid=true}
        steam_recipe.energy = 1
        steam_recipe.ingredients = {{type="fluid", name="water", amount=60}}
        steam_recipe.products = {{type="fluid", name="steam", amount=60}}
        steam_recipe.main_product = steam_recipe.products[1]

        generator_util.format_recipe_products_and_ingredients(steam_recipe)
        generator_util.add_recipe_tooltip(steam_recipe)
        generator_util.data_structure.insert(steam_recipe)
    end

    -- Custom handling for Space Exploration Arcosphere recipes
    local se_split_recipes = {"se-arcosphere-fracture", "se-naquium-processor", "se-naquium-tessaract",
        "se-space-dilation-data", "se-space-fold-data", "se-space-injection-data", "se-space-warp-data"}
    for _, recipe_name in pairs(se_split_recipes) do
        local recipe = generator_util.data_structure.get_prototype(recipe_name, nil)
        local alt_recipe = generator_util.data_structure.get_prototype(recipe_name .. "-alt", nil)
        if recipe and alt_recipe then
            recipe.custom = true
            generator_util.combine_recipes(recipe, alt_recipe)
            generator_util.multiply_recipe(recipe, 0.5)
            generator_util.add_recipe_tooltip(recipe)
            generator_util.data_structure.remove(alt_recipe)
        end
    end

    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end

function generator.recipes_second_pass()
    -- Check again if all recipes still have a machine to produce them after machine second pass
    local recipes_without_machine = {}
    for _, recipe in pairs(NEW.all_recipes.recipes) do
        if not NEW.all_machines.map[recipe.category] then
            recipes_without_machine[recipe.name] = true
        end
    end

    -- Actually remove unbuildable recipes
    for recipe_name, _ in pairs(recipes_without_machine) do
        generator_util.remove_mapped_element(NEW.all_recipes, "recipes", recipe_name)
    end
end

---@class FPItemPrototype
---@field name string
---@field type string
---@field sprite SpritePath
---@field localised_name LocalisedString
---@field hidden boolean
---@field stack_size uint?
---@field ingredient_only boolean
---@field temperature number
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup

-- Returns all relevant items and fluids
function generator.all_items()
    generator_util.data_structure.init("complex", "types", "items", "type")

    local function add_item(table, item)
        local type = item.proto.type
        local name = item.proto.name
        table[type] = table[type] or {}
        table[type][name] = table[type][name] or {}
        local item_details = table[type][name]
        -- Determine whether this item is used as a product at least once
        item_details.is_product = item_details.is_product or item.is_product
        item_details.is_rocket_part = item_details.is_rocket_part or item.is_rocket_part
        item_details.temperature = item.proto.temperature
    end

    -- Create a table containing every item that is either a product or an ingredient to at least one recipe
    local relevant_items = {}
    for _, recipe in pairs(NEW.all_recipes.recipes) do
        for _, product in pairs(recipe.products) do
            local is_rocket_part = (recipe.category == "rocket-building")
            add_item(relevant_items, {proto=product, is_product=true, is_rocket_part=is_rocket_part})
        end
        for _, ingredient in pairs(recipe.ingredients) do
            add_item(relevant_items, {proto=ingredient, is_product=false, is_rocket_part=false})
        end
    end

    -- Add all standard items
    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto_name = generator_util.format_temperature_name(item_details, item_name)
            local proto = game[type .. "_prototypes"][proto_name]  ---@type LuaItemPrototype
            if proto == nil then goto skip_item end

            local localised_name = generator_util.format_temperature_localised_name(item_details, proto)
            local stack_size = (type == "item") and proto.stack_size or nil
            local order = (item_details.temperature) and (proto.order .. item_details.temperature) or proto.order

            local hidden = false  -- "entity" types are never hidden
            if type == "item" then hidden = proto.has_flag("hidden")
            elseif type == "fluid" then hidden = proto.hidden end
            if item_details.is_rocket_part then hidden = false end

            local item = {
                name = item_name,
                type = type,
                sprite = type .. "/" .. proto.name,
                localised_name = localised_name,
                hidden = hidden,
                stack_size = stack_size,
                ingredient_only = not item_details.is_product,
                temperature = item_details.temperature,
                order = order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup)
            }

            generator_util.data_structure.insert(item)

            ::skip_item::
        end
    end

    generator_util.data_structure.generate_map(true)
    return generator_util.data_structure.get()
end


---@class FluidChannels
---@field input integer
---@field output integer

---@class MachineBurner
---@field effectivity double
---@field categories { [string]: boolean }

---@class FPMachinePrototype
---@field name string
---@field category string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field ingredient_limit integer
---@field fluid_channels FluidChannels
---@field speed double
---@field energy_type "burner" | "electric" | "void"
---@field energy_usage double
---@field energy_drain double
---@field emissions double
---@field built_by_item FPItemPrototype?
---@field base_productivity double
---@field allowed_effects AllowedEffects?
---@field module_limit integer
---@field launch_sequence_time number?
---@field burner MachineBurner?

-- Generates a table containing all machines for all categories
function generator.all_machines()
    generator_util.data_structure.init("complex", "categories", "machines", "category")

    ---@param category string
    ---@param proto LuaEntityPrototype
    local function generate_category_entry(category, proto)
        -- First, determine if there is a valid sprite for this machine
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite == nil then return {} end

        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local speed = proto.crafting_categories and proto.crafting_speed or proto.mining_speed

        -- Determine data related to the energy source
        local energy_type, emissions, burner = nil, 0, nil  -- emissions remain at 0 if no energy source is present
        local energy_usage, energy_drain = (proto.energy_usage or proto.max_energy_usage or 0), 0

        -- Determine the name of the item that actually builds this machine for the item requester
        -- There can technically be more than one, but bots use the first one, so I do too
        local built_by_item = (proto.items_to_place_this) and proto.items_to_place_this[1].name or nil

        -- Determine the details of this entities energy source
        local burner_prototype, fluid_burner_prototype = proto.burner_prototype, proto.fluid_energy_source_prototype
        if burner_prototype then
            energy_type = "burner"
            emissions = burner_prototype.emissions
            burner = {effectivity = burner_prototype.effectivity, categories = burner_prototype.fuel_categories}

        -- Only supports fluid energy that burns_fluid for now, as it works the same way as solid burners
        -- Also doesn't respect scale_fluid_usage and fluid_usage_per_tick for now, let the reports come
        elseif fluid_burner_prototype then
            emissions = fluid_burner_prototype.emissions

            if fluid_burner_prototype.burns_fluid and not fluid_burner_prototype.fluid_box.filter then
                energy_type = "burner"
                burner = {effectivity = fluid_burner_prototype.effectivity, categories = {["fluid-fuel"] = true}}

            else  -- Avoid adding this type of complex fluid energy as electrical energy
                energy_type = "void"
            end

        elseif proto.electric_energy_source_prototype then
            energy_type = "electric"
            energy_drain = proto.electric_energy_source_prototype.drain
            emissions = proto.electric_energy_source_prototype.emissions

        elseif proto.void_energy_source_prototype then
            energy_type = "void"
            emissions = proto.void_energy_source_prototype.emissions
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

        local machine = {
            name = proto.name,
            category = category,
            localised_name = proto.localised_name,
            sprite = sprite,
            ingredient_limit = (proto.ingredient_count or 255),
            fluid_channels = fluid_channels,
            speed = speed,
            energy_type = energy_type,
            energy_usage = energy_usage,
            energy_drain = energy_drain,
            emissions = emissions,
            built_by_item = built_by_item,
            base_productivity = (proto.base_productivity or 0),
            allowed_effects = generator_util.format_allowed_effects(proto.allowed_effects),
            module_limit = (proto.module_inventory_size or 0),
            launch_sequence_time = generator_util.determine_launch_sequence_time(proto),
            burner = burner
        }

        return machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if not proto.has_flag("hidden") and proto.crafting_categories and proto.energy_usage ~= nil
                and not generator_util.is_irrelevant_machine(proto) then
            for category, _ in pairs(proto.crafting_categories) do
                local machine = generate_category_entry(category, proto)
                generator_util.data_structure.insert(machine)
            end

        -- Add mining machines
        elseif proto.resource_categories then
            if not proto.has_flag("hidden") and proto.type ~= "character" then
                for category, enabled in pairs(proto.resource_categories) do
                    -- Only supports solid mining recipes for now (no oil, etc.)
                    if enabled and category ~= "basic-fluid" then
                        local machine = generate_category_entry(category, proto)
                        machine.mining = true
                        generator_util.data_structure.insert(machine)
                    end
                end
            end

        -- Add offshore pumps
        elseif proto.fluid then
            local machine = generate_category_entry(proto.name, proto)
            machine.speed = 1  -- pumping speed included in the recipe product-amount
            machine.category = proto.name  -- unique category for every offshore pump
            generator_util.data_structure.insert(machine)
        end

        -- Add machines that produce steam (ie. boilers)
        for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" and fluidbox.filter
                    and fluidbox.filter.name == "steam" and proto.target_temperature ~= nil then
                -- Exclude any boilers that use heat as their energy source
                if proto.burner_prototype or proto.electric_energy_source_prototype then
                    -- Find the corresponding input fluidbox
                    local input_fluidbox = nil
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

                        local temp_diff = proto.target_temperature - input_fluidbox.filter.default_temperature
                        local energy_per_unit = input_fluidbox.filter.heat_capacity * temp_diff
                        machine.speed = machine.energy_usage / energy_per_unit

                        generator_util.data_structure.insert(machine)

                        -- Add every boiler to the general steam category (steam without temperature)
                        local general_machine = util.table.deepcopy(machine)
                        general_machine.category = "general-steam"
                        generator_util.data_structure.insert(general_machine)
                    end
                end
            end
        end
    end

    local function sorting_function(a, b)
        if a.speed < b.speed then return true
        elseif a.speed > b.speed then return false
        elseif a.module_limit < b.module_limit then return true
        elseif a.module_limit > b.module_limit then return false
        elseif a.energy_usage < b.energy_usage then return true
        elseif a.energy_usage > b.energy_usage then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end

function generator.machines_second_pass()
    -- Go over all recipes to find unused categories
    local used_category_names = {}
    for _, recipe_proto in pairs(NEW.all_recipes.recipes) do
        used_category_names[recipe_proto.category] = true
    end

    local unused_category_names = {}
    for _, category in pairs(NEW.all_machines.categories) do
        if not used_category_names[category.name] then
            unused_category_names[category.name] = true
        end
    end

    -- Filter out burner machines that don't have any valid fuel categories
    for _, machine_category in pairs(NEW.all_machines.categories) do
        local invalid_machines = {}
        for _, machine in pairs(machine_category.machines) do
            if machine.energy_type == "burner" then
                local category_found = false
                for fuel_category in pairs(machine.burner.categories) do
                    if NEW.all_fuels.map[fuel_category] then category_found = true; break end
                end
                if not category_found then table.insert(invalid_machines, machine.name) end
            end
        end

        for _, machine_name in pairs(invalid_machines) do
            generator_util.remove_mapped_element(machine_category, "machines", machine_name)
        end

        -- If the category ends up empty because of this, make sure to remove it
        if not next(machine_category.machines) then
            unused_category_names[machine_category.name] = true
        end
    end

    for category_name, _ in pairs(unused_category_names) do
        generator_util.remove_mapped_element(NEW.all_machines, "categories", category_name)
    end


    -- Replace built_by_item names with prototype references
    local item_prototypes = NEW.all_items.types[NEW.all_items.map["item"]]
    for _, category in pairs(NEW.all_machines.categories) do
        for _, machine in pairs(category.machines) do
            if machine.built_by_item then
                local item_proto_id = item_prototypes.map[machine.built_by_item]
                machine.built_by_item = item_prototypes.items[item_proto_id]
            end
        end
    end
end


---@class FPBeltPrototype
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field rich_text string
---@field throughput double

-- Generates a table containing all available transport belts
function generator.all_belts()
    generator_util.data_structure.init("simple", "belts")

    local belt_filter = {{filter="type", type="transport-belt"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(belt_filter)) do
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite ~= nil then
            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                rich_text = "[entity=" .. proto.name .. "]",
                throughput = proto.belt_speed * 480
            }
        end
    end

    local function sorting_function(a, b)
        if a.throughput < b.throughput then return true
        elseif a.throughput > b.throughput then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


---@class FPFuelPrototype
---@field name string
---@field type "item" | "fluid"
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field category string | "fluid-fuel"
---@field fuel_value float
---@field stack_size uint?
---@field emissions_multiplier double

-- Generates a table containing all fuels that can be used in a burner
function generator.all_fuels()
    generator_util.data_structure.init("complex", "categories", "fuels", "category")

    -- Determine all the fuel categories that the machine prototypes use
    local used_fuel_categories = {}
    for _, categories in pairs(NEW.all_machines.categories) do
        for _, machine in pairs(categories.machines) do
            if machine.burner then
                for category_name, _ in pairs(machine.burner.categories) do
                    used_fuel_categories[category_name] = true
                end
            end
        end
    end

    local fuel_filter = {{filter="fuel-value", comparison=">", value=0},
        {filter="fuel-value", comparison="<", value=1e+21, mode="and"}}
    local new_item_types = NEW.all_items.types

    -- Add solid fuels
    local item_map = new_item_types[NEW.all_items.map["item"]].map
    local item_fuel_filter = fancytable.shallow_copy(fuel_filter)
    table.insert(item_fuel_filter, {filter="flag", flag="hidden", invert=true, mode="and"})

    for _, proto in pairs(game.get_filtered_item_prototypes(item_fuel_filter)) do
        -- Only use fuels that were actually detected/accepted to be items and find use in at least one machine
        if item_map[proto.name] and used_fuel_categories[proto.fuel_category] ~= nil then
            generator_util.data_structure.insert{
                name = proto.name,
                type = "item",
                localised_name = proto.localised_name,
                sprite = "item/" .. proto.name,
                category = proto.fuel_category,
                fuel_value = proto.fuel_value,
                stack_size = proto.stack_size,
                emissions_multiplier = proto.fuel_emissions_multiplier
            }
        end
    end

    -- Add liquid fuels
    local fluid_map = new_item_types[NEW.all_items.map["fluid"]].map
    local fluid_fuel_filter = fancytable.shallow_copy(fuel_filter)
    table.insert(fluid_fuel_filter, {filter="hidden", invert=true, mode="and"})

    for _, proto in pairs(game.get_filtered_fluid_prototypes(fluid_fuel_filter)) do
        -- Only use fuels that have actually been detected/accepted as fluids
        if fluid_map[proto.name] then
            generator_util.data_structure.insert{
                name = proto.name,
                type = "fluid",
                localised_name = proto.localised_name,
                sprite = "fluid/" .. proto.name,
                category = "fluid-fuel",
                fuel_value = proto.fuel_value,
                stack_size = nil,
                emissions_multiplier = proto.emissions_multiplier
            }
        end
    end

    local function sorting_function(a, b)
        if a.fuel_value < b.fuel_value then return true
        elseif a.fuel_value > b.fuel_value then return false
        elseif a.emissions_multiplier < b.emissions_multiplier then return true
        elseif a.emissions_multiplier > b.emissions_multiplier then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


---@class FPModulePrototype
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field category string
---@field tier uint
---@field effects ModuleEffects
---@field limitations { [string]: true }

-- Generates a table containing all available modules
function generator.all_modules()
    generator_util.data_structure.init("complex", "categories", "modules", "category")

    local module_filter = {{filter="type", type="module"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_item_prototypes(module_filter)) do
        local limitations = {}  -- Convert limitations-table to a [recipe_name] -> true format
        for _, recipe_name in pairs(proto.limitations) do limitations[recipe_name] = true end

        local sprite = "item/" .. proto.name
        if game.is_valid_sprite_path(sprite) then
            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = proto.category,
                tier = proto.tier,
                effects = proto.module_effects or {},
                limitations = limitations
            }
        end
    end

    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


---@class FPBeaconPrototype
---@field name string
---@field localised_string LocalisedString
---@field sprite SpritePath
---@field category "fp_beacon"
---@field built_by_item FPItemPrototype
---@field allowed_effects AllowedEffects
---@field module_limit uint
---@field effectivity double
---@field energy_usage double

-- Generates a table containing all available beacons
function generator.all_beacons()
    generator_util.data_structure.init("simple", "beacons")

    local item_prototypes = NEW.all_items.types[NEW.all_items.map["item"]]

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(beacon_filter)) do
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite ~= nil and proto.module_inventory_size and proto.distribution_effectivity > 0 then
            -- Beacons can refer to the actual item prototype right away because they are built after items are
            local items_to_place_this, built_by_item = proto.items_to_place_this, nil
            if items_to_place_this then
                local item_proto_id = item_prototypes.map[items_to_place_this[1].name]
                built_by_item = item_prototypes.items[item_proto_id]
            end

            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "fp_beacon",  -- custom category to be similar to machines
                built_by_item = built_by_item,
                allowed_effects = generator_util.format_allowed_effects(proto.allowed_effects),
                module_limit = proto.module_inventory_size,
                effectivity = proto.distribution_effectivity,
                energy_usage = proto.energy_usage or proto.max_energy_usage or 0
            }
        end
    end

    local function sorting_function(a, b)
        if a.module_limit < b.module_limit then return true
        elseif a.module_limit > b.module_limit then return false
        elseif a.effectivity < b.effectivity then return true
        elseif a.effectivity > b.effectivity then return false
        elseif a.energy_usage < b.energy_usage then return true
        elseif a.energy_usage > b.energy_usage then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


---@class FPWagonPrototype
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field rich_text string
---@field category "cargo-wagon" | "fluid-wagon"
---@field storage number

-- Generates a table containing all available cargo and fluid wagons
function generator.all_wagons()
    generator_util.data_structure.init("complex", "categories", "wagons", "category")

    -- Add cargo wagons
    local cargo_wagon_filter = {{filter="type", type="cargo-wagon"},
        {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(cargo_wagon_filter)) do
        local inventory_size = proto.get_inventory_size(defines.inventory.cargo_wagon)
        if inventory_size > 0 then
            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = generator_util.determine_entity_sprite(proto),
                rich_text = "[entity=" .. proto.name .. "]",
                category = "cargo-wagon",
                storage = inventory_size
            }
        end
    end

    -- Add fluid wagons
    local fluid_wagon_filter = {{filter="type", type="fluid-wagon"},
        {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(fluid_wagon_filter)) do
        if proto.fluid_capacity > 0 then
            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = generator_util.determine_entity_sprite(proto),
                rich_text = "[entity=" .. proto.name .. "]",
                category = "fluid-wagon",
                storage = proto.fluid_capacity
            }
        end
    end

    local function sorting_function(a, b)
        if a.storage < b.storage then return true
        elseif a.storage > b.storage then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end

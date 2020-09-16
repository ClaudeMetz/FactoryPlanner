require("data.handlers.generator_util")

generator = {}

-- ** TOP LEVEL **
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

    -- Adding all standard recipes
    local recipe_filter = {{filter="energy", comparison=">", value=0},
      {filter="energy", comparison="<", value=1e+21, mode="and"}}
    for recipe_name, proto in pairs(game.get_filtered_recipe_prototypes(recipe_filter)) do
        local category_id = new.all_machines.map[proto.category]
        -- Avoid any recipes that have no machine to produce them, or are annoying
        if category_id ~= nil and not generator_util.is_annoying_recipe(proto) then
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
                barreling = generator_util.is_barreling_recipe(proto),
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
    local rocket_silo_inputs = {}
    for _, item in pairs(game.item_prototypes) do  -- (no filter to detect this possible)
        if table_size(item.rocket_launch_products) > 0 then
            table.insert(rocket_silo_inputs, item)
        end
    end

    -- Cache them here so they don't have to be recreated over and over
    local item_prototypes, recipe_prototypes = game.item_prototypes, game.recipe_prototypes

    -- Adding mining recipes
    for _, proto in pairs(game.entity_prototypes) do
        -- Adds all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category then
            local produces_solid = false
            local products = proto.mineable_properties.products
            for _, product in pairs(products) do  -- detects all solid mining recipes
                if product.type == "item" then produces_solid = true end
            end

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
            -- Add recipe for all 'launchable' items
            for _, item in pairs(rocket_silo_inputs) do
                local fixed_recipe = recipe_prototypes[proto.fixed_recipe]
                if fixed_recipe ~= nil then
                    local silo_product = item_prototypes[item.rocket_launch_products[1].name]

                    local recipe = custom_recipe()
                    recipe.name = "impostor-silo-" .. proto.name .. "-item-" .. item.name
                    recipe.localised_name = silo_product.localised_name
                    recipe.sprite = "item/" .. silo_product.name
                    recipe.category = next(proto.crafting_categories, nil)  -- hopefully this stays working
                    recipe.energy = fixed_recipe.energy * proto.rocket_parts_required
                    recipe.subgroup = {name="science-pack", order="g", valid=true}
                    recipe.order = "x-silo-" .. proto.order .. "-" .. item.order

                    recipe.ingredients = fixed_recipe.ingredients
                    for _, ingredient in pairs(recipe.ingredients) do
                        ingredient.amount = ingredient.amount * proto.rocket_parts_required
                    end
                    table.insert(recipe.ingredients, {type="item", name=item.name, amount=1, ignore_productivity=true})
                    recipe.products = item.rocket_launch_products
                    recipe.main_product = recipe.products[1]

                    generator_util.format_recipe_products_and_ingredients(recipe)
                    generator_util.add_recipe_tooltip(recipe)
                    generator_util.data_structure.insert(recipe)
                end
            end
        end

        -- Adds a recipe for producing steam from a boiler
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

    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


-- Returns all relevant items and fluids
function generator.all_items()
    generator_util.data_structure.init("complex", "types", "items", "type")

    local function add_item(table, item)
        local type = item.proto.type
        local name = item.proto.name
        table[type] = table[type] or {}
        table[type][name] = table[type][name] or {}
        -- Determine whether this item is used as a product at least once
        table[type][name].is_product = table[type][name].is_product or item.is_product
        table[type][name].temperature = item.proto.temperature
    end

    -- Create a table containing every item that is either a product or an ingredient to at least one recipe
    local relevant_items = {}
    for _, recipe in pairs(new.all_recipes.recipes) do
        for _, product in pairs(recipe.products) do
            add_item(relevant_items, {proto=product, is_product=true})
        end
        for _, ingredient in pairs(recipe.ingredients) do
            add_item(relevant_items, {proto=ingredient, is_product=false})
        end
    end

    -- Adding all standard items
    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto_name = generator_util.format_temperature_name(item_details, item_name)
            local proto = game[type .. "_prototypes"][proto_name]
            local localised_name = generator_util.format_temperature_localised_name(item_details, proto)
            local order = (item_details.temperature) and (proto.order .. item_details.temperature) or proto.order

            local hidden = false  -- "entity" types are never hidden
            if type == "item" then hidden = proto.has_flag("hidden")
            elseif type == "fluid" then hidden = proto.hidden end

            local item = {
                name = item_name,
                type = type,
                sprite = type .. "/" .. proto.name,
                localised_name = localised_name,
                hidden = hidden,
                ingredient_only = not item_details.is_product,
                temperature = item_details.temperature,
                order = order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup)
            }

            generator_util.add_item_tooltip(item)
            generator_util.data_structure.insert(item)
        end
    end

    generator_util.data_structure.generate_map(true)
    return generator_util.data_structure.get()
end


-- Generates a table containing all machines for all categories
function generator.all_machines()
    generator_util.data_structure.init("complex", "categories", "machines", "category")

    local function generate_category_entry(category, proto)
        -- First, determine if there is a valid sprite for this machine
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite == nil then return nil end

        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local speed = proto.crafting_categories and proto.crafting_speed or proto.mining_speed

        -- Determine data related to the energy source
        local energy_type, emissions, burner = nil, 0, nil  -- emissions remain at 0 if no energy source is present
        local energy_usage = proto.energy_usage or proto.max_energy_usage or 0

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
            emissions = emissions,
            base_productivity = (proto.base_productivity or 0),
            allowed_effects = generator_util.format_allowed_effects(proto.allowed_effects),
            module_limit = (proto.module_inventory_size or 0),
            is_rocket_silo = (proto.rocket_parts_required ~= nil),
            burner = burner
        }

        return machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if not proto.has_flag("hidden") and proto.crafting_categories and proto.energy_usage ~= nil then
            for category, _ in pairs(proto.crafting_categories) do
                local machine = generate_category_entry(category, proto)
                generator_util.data_structure.insert(machine)
            end

        -- Add mining machines
        elseif proto.resource_categories then
            for category, enabled in pairs(proto.resource_categories) do
                -- Only supports solid mining recipes for now (no oil, etc.)
                if enabled and category ~= "basic-fluid" then
                    local machine = generate_category_entry(category, proto)
                    machine.mining = true
                    generator_util.data_structure.insert(machine)
                end
            end

        -- Add offshore pumps
        elseif proto.fluid then
            local machine = generate_category_entry(proto.name, proto)
            machine.speed = 1  -- pumping speed included in the recipe product-amount
            machine.category = proto.name  -- unique category for every offshort pump
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
        elseif a.energy_usage < b.energy_usage then return true
        elseif a.energy_usage > b.energy_usage then return false
        elseif a.module_limit < b.module_limit then return true
        elseif a.module_limit > b.module_limit then return false end
    end

    generator_util.data_structure.sort(sorting_function)
    generator_util.data_structure.generate_map(false)
    return generator_util.data_structure.get()
end


-- Generates a table containing all available transport belts
function generator.all_belts()
    generator_util.data_structure.init("simple", "belts")

    local belt_filter = {{filter="type", type="transport-belt"}}
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


-- Generates a table containing all fuels that can be used in a burner
function generator.all_fuels()
    generator_util.data_structure.init("complex", "categories", "fuels", "category")

    -- Determine all the fuel categories that the machine prototypes use
    local used_fuel_categories = {}
    for _, categories in pairs(new.all_machines.categories) do
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

    -- Add solid fuels
    local item_map = new.all_items.types[new.all_items.map["item"]].map
    for _, proto in pairs(game.get_filtered_item_prototypes(fuel_filter)) do
        -- Only use fuels that were actually detected/accepted to be items and find use in at least one machine
        if item_map[proto.name] and used_fuel_categories[proto.fuel_category] ~= nil then
            generator_util.data_structure.insert{
                name = proto.name,
                type = "item",
                localised_name = proto.localised_name,
                sprite = "item/" .. proto.name,
                category = proto.fuel_category,
                fuel_value = proto.fuel_value,
                emissions_multiplier = proto.fuel_emissions_multiplier
            }
        end
    end

    -- Add liquid fuels
    local fluid_map = new.all_items.types[new.all_items.map["fluid"]].map
    for _, proto in pairs(game.get_filtered_fluid_prototypes(fuel_filter)) do
        -- Only use fuels that have actually been detected/accepted as fluids
        if fluid_map[proto.name] then
            generator_util.data_structure.insert{
                name = proto.name,
                type = "fluid",
                localised_name = proto.localised_name,
                sprite = "fluid/" .. proto.name,
                category = "fluid-fuel",
                fuel_value = proto.fuel_value,
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


-- Generates a table containing all available beacons
function generator.all_beacons()
    generator_util.data_structure.init("simple", "beacons")

    local beacon_filter = {{filter="type", type="beacon"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    for _, proto in pairs(game.get_filtered_entity_prototypes(beacon_filter)) do
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite ~= nil then
            generator_util.data_structure.insert{
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "fp_beacon",  -- custom category to be similar to machines
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
local generator_util = require("backend.handlers.generator_util")

local generator = {
    machines = {},
    recipes = {},
    items = {},
    fuels = {},
    belts = {},
    wagons = {},
    modules = {},
    beacons = {}
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
---@field ingredient_limit integer
---@field fluid_channels FluidChannels
---@field speed double
---@field energy_type "burner" | "electric" | "void"
---@field energy_usage double
---@field energy_drain double
---@field emissions double
---@field built_by_item FPItemPrototype?
---@field effect_receiver EffectReceiver?
---@field allowed_effects AllowedEffects
---@field module_limit integer
---@field launch_sequence_time number?
---@field burner MachineBurner?
---@field resource_drain_rate number?

---@class FluidChannels
---@field input integer
---@field output integer

---@class MachineBurner
---@field effectivity double
---@field categories { [string]: boolean }

-- Generates a table containing all machines for all categories
---@return NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.generate()
    local machines = {}  ---@type NamedPrototypesWithCategory<FPMachinePrototype>

    ---@param category string
    ---@param proto LuaEntityPrototype
    ---@return FPMachinePrototype?
    local function generate_category_entry(category, proto)
        -- First, determine if there is a valid sprite for this machine
        local sprite = generator_util.determine_entity_sprite(proto)
        if sprite == nil then return end

        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local speed = proto.crafting_categories and proto.get_crafting_speed() or proto.mining_speed

        -- Determine data related to the energy source
        local energy_type, emissions = "", 0  -- emissions remain at 0 if no energy source is present
        local burner = nil  ---@type MachineBurner
        local energy_usage, energy_drain = (proto.energy_usage or proto.active_energy_usage or 0), 0

        -- Determine the name of the item that actually builds this machine for the item requester
        -- There can technically be more than one, but bots use the first one, so I do too
        local built_by_item = (proto.items_to_place_this) and proto.items_to_place_this[1].name or nil

        -- Determine the details of this entities energy source
        local burner_prototype, fluid_burner_prototype = proto.burner_prototype, proto.fluid_energy_source_prototype
        if burner_prototype then
            energy_type = "burner"
            emissions = burner_prototype.emissions_per_joule["pollution"]
            burner = {effectivity = burner_prototype.effectivity, categories = burner_prototype.fuel_categories}

        -- Only supports fluid energy that burns_fluid for now, as it works the same way as solid burners
        -- Also doesn't respect scale_fluid_usage and fluid_usage_per_tick for now, let the reports come
        elseif fluid_burner_prototype then
            emissions = fluid_burner_prototype.emissions_per_joule["pollution"]

            if fluid_burner_prototype.burns_fluid and not fluid_burner_prototype.fluid_box.filter then
                energy_type = "burner"
                burner = {effectivity = fluid_burner_prototype.effectivity, categories = {["fluid-fuel"] = true}}

            else  -- Avoid adding this type of complex fluid energy as electrical energy
                energy_type = "void"
            end

        elseif proto.electric_energy_source_prototype then
            energy_type = "electric"
            energy_drain = proto.electric_energy_source_prototype.drain
            emissions = proto.electric_energy_source_prototype.emissions_per_joule["pollution"]

        elseif proto.void_energy_source_prototype then
            energy_type = "void"
            emissions = proto.void_energy_source_prototype.emissions_per_joule["pollution"]
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
            localised_name = proto.localised_name,
            sprite = sprite,
            category = category,
            ingredient_limit = (proto.ingredient_count or 255),
            fluid_channels = fluid_channels,
            speed = speed,
            energy_type = energy_type,
            energy_usage = energy_usage,
            energy_drain = energy_drain,
            emissions = emissions,
            built_by_item = built_by_item,
            effect_receiver = proto.effect_receiver,
            allowed_effects = proto.allowed_effects or {},
            module_limit = (proto.module_inventory_size or 0),
            launch_sequence_time = generator_util.determine_launch_sequence_time(proto),
            burner = burner
        }
        generator_util.check_machine_effects(machine)

        return machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if --[[ not proto.hidden and ]] proto.crafting_categories and proto.energy_usage ~= nil
                and not generator_util.is_irrelevant_machine(proto) then
            for category, _ in pairs(proto.crafting_categories) do
                local machine = generate_category_entry(category, proto)
                if machine then insert_prototype(machines, machine, machine.category) end
            end

        -- Add mining machines
        elseif proto.resource_categories then
            if --[[ not proto.hidden and ]] proto.type ~= "character" then
                for category, enabled in pairs(proto.resource_categories) do
                    -- Only supports solid mining recipes for now (no oil, etc.)
                    if enabled and category ~= "basic-fluid" then
                        local machine = generate_category_entry(category, proto)
                        if machine then
                            machine.resource_drain_rate = proto.resource_drain_rate_percent / 100
                            insert_prototype(machines, machine, machine.category)
                        end
                    end
                end
            end

        -- Add offshore pumps
        --[[ elseif proto.fluid then
            local machine = generate_category_entry(proto.name, proto)
            if machine then
                machine.speed = 1  -- pumping speed included in the recipe product-amount
                machine.category = proto.name  -- unique category for every offshore pump
                insert_prototype(machines, machine, machine.category)
            end ]]
        end

        -- Add machines that produce steam (ie. boilers)
        for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
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
        end
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


---@class FPUnformattedRecipePrototype: FPPrototype
---@field data_type "recipes"
---@field category string
---@field energy double
---@field emissions_multiplier double
---@field ingredients FPIngredient[]
---@field products Product[]
---@field main_product Product?
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

---@class FPRecipePrototype: FPUnformattedRecipePrototype
---@field ingredients FormattedRecipeItem[]
---@field products FormattedRecipeItem[]
---@field main_product FormattedRecipeItem?

---@class FPIngredient: Ingredient
---@field ignore_productivity boolean

-- Returns all standard recipes + custom mining, steam and rocket recipes
---@return NamedPrototypes<FPRecipePrototype>
function generator.recipes.generate()
    local recipes = {}   ---@type NamedPrototypes<FPRecipePrototype>

    ---@return FPUnformattedRecipePrototype
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
                ingredients = proto.ingredients,
                products = proto.products,
                main_product = proto.main_product,
                allowed_effects = proto.allowed_effects or {},
                maximum_productivity = 0.5,--proto.maximum_productivity,
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

            generator_util.format_recipe_products_and_ingredients(recipe)
            ---@cast recipe FPRecipePrototype
            insert_prototype(recipes, recipe, nil)
        end
    end


    -- Determine all the items that can be inserted usefully into a rocket silo
    --[[ local launch_products_filter = {{filter="has-rocket-launch-products"}}
    local rocket_silo_inputs = {}  ---@type LuaItemPrototype[]
    for _, item in pairs(game.get_filtered_item_prototypes(launch_products_filter)) do
        if next(item.rocket_launch_products) then
            table.insert(rocket_silo_inputs, item)
        end
    end

    -- Localize them here so they don't have to be recreated over and over
    local item_prototypes, recipe_prototypes = game.item_prototypes, game.recipe_prototypes ]]

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
                recipe.localised_name = {"", proto.localised_name, " ", {"fp.mining_recipe"}}
                recipe.sprite = products[1].type .. "/" .. products[1].name
                recipe.order = proto.order
                recipe.subgroup = {name="mining", order="y", valid=true}
                recipe.category = proto.resource_category
                -- Set energy to mining time so the forumla for the machine_count works out
                recipe.energy = proto.mineable_properties.mining_time
                recipe.ingredients = {{type="entity", name=proto.name, amount=1, ignore_productivity=false}}
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
                ---@cast recipe FPRecipePrototype
                generator_util.add_recipe_tooltip(recipe)
                insert_prototype(recipes, recipe, nil)

            --else
                -- crude-oil and angels-natural-gas go here (not interested atm)
            end

            ::incompatible_proto::

        -- Add offshore-pump fluid recipes
        --[[ elseif proto.fluid then
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
            ---@cast recipe FPRecipePrototype
            generator_util.add_recipe_tooltip(recipe)
            insert_prototype(recipes, recipe, nil) ]]

        -- Detect all the implicit rocket silo recipes
        --[[ elseif proto.rocket_parts_required ~= nil then
            local fixed_recipe = recipe_prototypes[proto.fixed_recipe --[[@as string] ] ]
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
                    recipe.energy = fixed_recipe.energy * proto.rocket_parts_required --[[@as number] ]
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
                    ---@cast recipe FPRecipePrototype
                    generator_util.add_recipe_tooltip(recipe)
                    insert_prototype(recipes, recipe, nil)
                end

                -- Modify recipe for all rocket parts so they represent a full launch
                -- This is needed so the launch sequence times can be incorporated correctly
                local rocket_part_recipe = recipes[fixed_recipe.name]
                if rocket_part_recipe then
                    generator_util.multiply_recipe(rocket_part_recipe, proto.rocket_parts_required)
                end
            end ]]
        end

        -- Add a recipe for producing steam from a boiler
        local existing_recipe_names = {}  ---@type { [string]: boolean }
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
                        ---@cast recipe FPRecipePrototype
                        generator_util.add_recipe_tooltip(recipe)
                        insert_prototype(recipes, recipe, nil)
                    end
                end
            end
        end
    end

    -- Add a general steam recipe that works with every boiler
    if game["fluid_prototypes"]["steam"] then  -- make sure the steam prototype exists
        local recipe = custom_recipe()
        recipe.name = "fp-general-steam"
        recipe.localised_name = {"fluid-name.steam"}
        recipe.sprite = "fluid/steam"
        recipe.category = "general-steam"
        recipe.order = "z-0"
        recipe.subgroup = {name="fluids", order="z", valid=true}
        recipe.energy = 1
        recipe.ingredients = {{type="fluid", name="water", amount=60}}
        recipe.products = {{type="fluid", name="steam", amount=60}}
        recipe.main_product = recipe.products[1]

        generator_util.format_recipe_products_and_ingredients(recipe)
        ---@cast recipe FPRecipePrototype
        generator_util.add_recipe_tooltip(recipe)
        insert_prototype(recipes, recipe, nil)
    end

    -- Custom handling for Space Exploration Arcosphere recipes
    --[[ local se_split_recipes = {"se-arcosphere-fracture", "se-naquium-processor", "se-naquium-tessaract",
        "se-space-dilation-data", "se-space-fold-data", "se-space-injection-data", "se-space-warp-data"}
    for _, recipe_name in pairs(se_split_recipes) do
        local recipe, alt_recipe = recipes[recipe_name], recipes[recipe_name .. "-alt"]
        if recipe and alt_recipe then
            recipe.custom = true
            generator_util.combine_recipes(recipe, alt_recipe)
            generator_util.multiply_recipe(recipe, 0.5)
            generator_util.add_recipe_tooltip(recipe)
            remove_prototype(recipes, alt_recipe.name, nil)
        end
    end ]]

    return recipes
end

---@param recipes NamedPrototypes<FPRecipePrototype>
function generator.recipes.second_pass(recipes)
    local machines = global.prototypes.machines
    -- Check again if all recipes still have a machine to produce them after machine second pass
    for _, recipe in pairs(recipes) do
        if not machines[recipe.category] then
            remove_prototype(recipes, recipe.name, nil)
        end
    end
end


---@class FPItemPrototype: FPPrototypeWithCategory
---@field data_type "items"
---@field type "item" | "fluid" | "entity"
---@field hidden boolean
---@field stack_size uint?
---@field ingredient_only boolean
---@field temperature number
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup

---@class RelevantItem
---@field proto FormattedRecipeItem
---@field is_product boolean
---@field is_rocket_part boolean
---@field temperature number?

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
        item_details.is_rocket_part = item_details.is_rocket_part or item.is_rocket_part
        item_details.temperature = item.proto.temperature
    end

    -- Create a table containing every item that is either a product or an ingredient to at least one recipe
    local relevant_items = {}  ---@type RelevantItems
    for _, recipe_proto in pairs(global.prototypes.recipes) do
        for _, product in pairs(recipe_proto.products) do
            local is_rocket_part = (recipe_proto.category == "rocket-building")
            add_item(relevant_items, {proto=product, is_product=true, is_rocket_part=is_rocket_part})
        end
        for _, ingredient in pairs(recipe_proto.ingredients) do
            add_item(relevant_items, {proto=ingredient, is_product=false, is_rocket_part=false})
        end
    end

    -- Add all standard items
    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto_name = generator_util.format_temperature_name(item_details, item_name)
            local proto = game[type .. "_prototypes"][proto_name]  ---@type LuaItemPrototype | LuaFluidPrototype
            if proto == nil then goto skip_item end

            local localised_name = generator_util.format_temperature_localised_name(item_details, proto)
            if type == "entity" then localised_name = {"", localised_name, " ", {"fp.ore_deposit"}} end
            local stack_size = (type == "item") and proto.stack_size or nil
            local order = (item_details.temperature) and (proto.order .. item_details.temperature) or proto.order

            local hidden = false  -- "entity" types are never hidden
            if type == "item" or type == "fluid" then hidden = proto.hidden end
            if item_details.is_rocket_part then hidden = false end

            local item = {
                name = item_name,
                localised_name = localised_name,
                sprite = type .. "/" .. proto.name,
                type = type,
                hidden = hidden,
                stack_size = stack_size,
                ingredient_only = not item_details.is_product,
                temperature = item_details.temperature,
                order = order,
                group = generator_util.generate_group_table(proto.group),
                subgroup = generator_util.generate_group_table(proto.subgroup)
            }

            insert_prototype(items, item, item.type)

            ::skip_item::
        end
    end

    return items
end


---@class FPFuelPrototype: FPPrototypeWithCategory
---@field data_type "fuels"
---@field type "item" | "fluid"
---@field category string | "fluid-fuel"
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
---@field rich_text string
---@field category "cargo-wagon" | "fluid-wagon"
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
                rich_text = "[entity=" .. proto.name .. "]",
                category = "cargo-wagon",
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
                rich_text = "[entity=" .. proto.name .. "]",
                category = "fluid-wagon",
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
---@field category "fp_beacon"
---@field built_by_item FPItemPrototype
---@field allowed_effects AllowedEffects
---@field module_limit uint
---@field effectivity double
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
                category = "fp_beacon",  -- custom category to be similar to machines
                built_by_item = built_by_item,
                allowed_effects = proto.allowed_effects,
                module_limit = proto.module_inventory_size,
                effectivity = proto.distribution_effectivity,
                profile = proto.profile,
                energy_usage = proto.energy_usage or proto.max_energy_usage or 0
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


return generator

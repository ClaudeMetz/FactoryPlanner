local generator = {
    util = require("backend.handlers.generator_util"),

    recipes = {},
    items = {},
    machines = {},
    fuels = {},
    belts = {},
    pumps = {},
    silos = {},
    wagons = {},
    modules = {},
    beacons = {},
    locations = {},
    qualities = {}
}

-- Data collected during recipe generation, reused by later generator stages
local resource_deposits = {}  ---@type LuaEntityPrototype[]
local rocket_parts = {}  ---@type table<string, boolean>
local pumped_tiles = {}  ---@type LuaTilePrototype[]
local tile_can_have_plant = {}  ---@type table<string, string[]>


---@class FPPrototype
---@field id integer
---@field data_type DataType
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field factoriopedia_id { type: FactoriopediaIDType, name: string}?

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


---@class FPRecipePrototype: FPPrototype
---@field data_type "recipes"
---@field categories table<string, boolean>
---@field combined_category string
---@field energy double
---@field emissions_multiplier double
---@field emissions_per_craft EmissionsMap?
---@field ingredients Ingredient[]
---@field products FormattedProduct[]
---@field main_product FormattedProduct?
---@field allowed_effects AllowedEffects?
---@field allowed_module_categories table<string, boolean>?
---@field maximum_productivity IntegerEffectValue
---@field productivity_recipe string?
---@field type_counts { products: ItemTypeCounts, ingredients: ItemTypeCounts }
---@field surface_conditions SurfaceCondition[]?
---@field recycling boolean
---@field barreling boolean
---@field enabling_technologies string[]?
---@field heat_capacity double?
---@field custom boolean
---@field location_restricted boolean?
---@field enabled_from_the_start boolean
---@field hidden boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup
---@field tooltip LocalisedString?

---@return NamedPrototypes<FPRecipePrototype>
function generator.recipes.generate()
    local recipes = {}   ---@type NamedPrototypes<FPRecipePrototype>

    ---@return FPRecipePrototype
    local function custom_recipe()
        ---@diagnostic disable-next-line: missing-fields
        local recipe = {
            combined_category = "",  -- filled in by machine generator
            custom = true,
            enabled_from_the_start = true,
            hidden = false,
            maximum_productivity = 2^53,
            emissions_multiplier = 1
        }  ---@type FPRecipePrototype
        generator.util.add_default_groups(recipe)
        return recipe
    end

    -- Determine researchable & productivity recipes
    local researchable_recipes = {}  ---@type table<string, string[]>
    local productivity_recipes = {}  ---@type table<string, boolean>
    local any_mining_productivity = false
    local tech_filter = {{filter="hidden", invert=true}, {filter="has-effects", mode="and"}}
    for _, tech_proto in pairs(prototypes.get_technology_filtered(tech_filter)) do
        for _, effect in pairs(tech_proto.effects) do
            if effect.type == "unlock-recipe" then
                local recipe_name = effect.recipe
                researchable_recipes[recipe_name] = researchable_recipes[recipe_name] or {}
                table.insert(researchable_recipes[recipe_name], tech_proto.name)
            elseif effect.type == "change-recipe-productivity" then
                productivity_recipes[effect.recipe] = true
            elseif effect.type == "mining-drill-productivity-bonus" then
                any_mining_productivity = true
            end
        end
    end

    -- Determine plant->seed map and item->launch_result map
    local plant_seed_map, launch_products = {}, {}
    for _, item_proto in pairs(prototypes.item) do
        if item_proto.plant_result then
            plant_seed_map[item_proto.plant_result.name] = item_proto.name
        elseif #item_proto.rocket_launch_products > 0 then
            launch_products[item_proto.name] = item_proto.rocket_launch_products
        end
    end

    local recycling_recipes = storage.integrations.recycling_recipes
    local compacting_recipes = storage.integrations.compacting_recipes

    -- Add all standard recipes
    local recipe_filter = {{filter="energy", comparison=">", value=0},
        {filter="energy", comparison="<", value=1e+21, mode="and"}}
    for recipe_name, proto in pairs(prototypes.get_recipe_filtered(recipe_filter)) do
        if not proto.parameter then  -- not an option on the filter
            local categories = {}
            for _, category in pairs(proto.categories) do categories[category] = true end

            ---@diagnostic disable-next-line: missing-fields
            local recipe = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "recipe/" .. proto.name,
                categories = categories,
                combined_category = "",  -- filled in by machine generator
                energy = proto.energy,
                emissions_multiplier = proto.emissions_multiplier,
                allowed_effects = proto.allowed_effects,  -- can be nil
                allowed_module_categories = proto.allowed_module_categories,  -- can be nil
                maximum_productivity = math.floor(proto.maximum_productivity
                    * MAGIC_NUMBERS.effect_precision + 1e-4),
                productivity_recipe = (productivity_recipes[proto.name]) and proto.name or nil,
                surface_conditions = proto.surface_conditions,
                recycling = recycling_recipes[proto.name],
                barreling = compacting_recipes[proto.name],
                enabling_technologies = researchable_recipes[recipe_name],  -- can be nil
                custom = false,
                enabled_from_the_start = proto.enabled,
                hidden = proto.hidden,
                order = proto.order,
                group = generator.util.generate_group_table(proto.group),
                subgroup = generator.util.generate_group_table(proto.subgroup)
            }  ---@type FPRecipePrototype

            generator.util.format_recipe(recipe, proto.products, proto.main_product, proto.ingredients)
            insert_prototype(recipes, recipe, nil)
        end
    end

    local first_generator = nil  ---@type string?
    local pumped_fixed_fluids = {}  ---@type table<string, boolean>
    local boiler_recipes = {}  ---@type table<string, FPRecipePrototype>

    local entity_filter = {{filter="hidden", invert=true}}
    for _, proto in pairs(prototypes.get_entity_filtered(entity_filter)) do
        -- Note the alphabetically first power generating machine for the electricity recipe below
        if proto.type == "generator" or proto.type == "burner-generator" then
            if first_generator == nil or proto.name < first_generator then first_generator = proto.name end
        end

        -- Recipes fixed to machines are duplicated with a special category
        if proto.crafting_categories and proto.energy_usage and proto.fixed_recipe then
            local recipe = recipes[proto.fixed_recipe.name]
            if recipe ~= nil then
                local category = proto.name .. "-using-" .. recipe.name
                local recipe_copy = lib.flib.deep_copy(recipe)
                recipe_copy.name = recipe.name .. "-for-" .. proto.name
                recipe_copy.categories = {[category] = true}
                recipe_copy.factoriopedia_id = {type="recipe", name=recipe.name}
                recipe_copy.custom = true
                insert_prototype(recipes, recipe_copy, nil)
            end
        end

        if proto.type == "resource" then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end
            local main_product = products[1]  ---@as Product

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.factoriopedia_id = {type="entity", name=proto.name}
            recipe.localised_name = {"", proto.localised_name, " ", {"fp.mining_recipe"}}
            recipe.sprite = main_product.type .. "/" .. main_product.name
            recipe.order = proto.order
            recipe.categories = {[proto.resource_category] = true}
            recipe.allowed_effects = {speed=true, productivity=true, quality=true, consumption=true, pollution=true}
            recipe.productivity_recipe = (any_mining_productivity) and "custom-mining" or nil
            recipe.energy = (proto.infinite_resource) and 0 or proto.mineable_properties.mining_time
            recipe.location_restricted = true

            local ingredients = {{type="entity", name="custom-" .. proto.name, amount=1}--[[@as Ingredient]]}

            if not proto.infinite_resource and proto.mineable_properties.required_fluid then
                table.insert(ingredients, {
                    type = "fluid",
                    name = proto.mineable_properties.required_fluid,
                    -- fluid_amount is given for a 'set' of mining ops, with a set being 10 ore
                    amount = proto.mineable_properties.fluid_amount--[[@cast -nil]] / 10
                })
            end

            generator.util.format_recipe(recipe, products, main_product, ingredients)
            insert_prototype(recipes, recipe, nil)

            -- Note the deposit so item generation can create its custom item
            table.insert(resource_deposits, proto)

            ::incompatible_proto::

        -- Add offshore pump recipes based on fixed fluids
        elseif proto.type == "offshore-pump" then
            local fluid_box = proto.fluidbox_prototypes[1]
            local fluid = fluid_box and fluid_box.filter
            -- Offshore pumps producing the same fluid can share a recipe
            if fluid ~= nil and not pumped_fixed_fluids[fluid.name] then
                pumped_fixed_fluids[fluid.name] = true

                local recipe = custom_recipe()
                recipe.name = "impostor-" .. fluid.name .. "-pumped"
                recipe.factoriopedia_id = {type="fluid", name=fluid.name}
                recipe.localised_name = {"", fluid.localised_name, " ", {"fp.pumping_recipe"}}
                recipe.sprite = "fluid/" .. fluid.name
                recipe.order = fluid.order
                recipe.categories = {["offshore-pump-" .. fluid.name] = true}
                recipe.energy = 1

                local products = {{type="fluid", name=fluid.name, amount=60,
                    temperature=fluid.default_temperature}--[[@as Product]]}
                generator.util.format_recipe(recipe, products, products[1], {})
                insert_prototype(recipes, recipe, nil)
            end

        -- Add agricultural tower recipes
        elseif proto.type == "plant" then
            local products = proto.mineable_properties.products
            if not products then goto incompatible_proto end
            local seed_name = plant_seed_map[proto.name]
            if not seed_name then goto incompatible_proto end
            local main_product = products[1]  ---@as Product

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.factoriopedia_id = {type="entity", name=proto.name}
            recipe.localised_name = {"", proto.localised_name, " ", {"fp.planting_recipe"}}
            recipe.sprite = main_product.type .. "/" .. main_product.name
            recipe.order = proto.order
            recipe.categories = {["agricultural-tower"] = true}
            recipe.energy = proto.growth_ticks--[[@cast -nil]] / 60
            recipe.location_restricted = true

            -- Add the plant prototype name to the list of tiles it can be planted on
            if proto.autoplace_specification then
                for _, tile_restriction in pairs(proto.autoplace_specification.tile_restriction or {}) do
                    if tile_restriction.first then
                        tile_can_have_plant[tile_restriction.first] = tile_can_have_plant[tile_restriction.first] or {}
                        table.insert(tile_can_have_plant[tile_restriction.first], proto.name)
                    end
                end
            end

            -- Each craft releases the harvest emissions plus a full growth period of the plant's emissions
            recipe.emissions_per_craft = {}
            for pollutant, amount in pairs(proto.harvest_emissions or {}) do
                recipe.emissions_per_craft[pollutant] = amount
            end
            for pollutant, amount in pairs(proto.emissions_per_second or {}) do
                recipe.emissions_per_craft[pollutant] = (recipe.emissions_per_craft[pollutant] or 0)
                    + (amount * recipe.energy)
            end

            local ingredients = {
                {type="item", name=seed_name, amount=1},
                {type="entity", name="custom-agriculture-square", amount=recipe.energy}
            }
            generator.util.format_recipe(recipe, products, main_product, ingredients)
            insert_prototype(recipes, recipe, nil)

            ::incompatible_proto::

        elseif proto.type == "rocket-silo" then
            local parts_recipes = generator.util.silo_parts_recipes(proto, recipes)
            -- Silos that can build several kinds of part need one recipe per part
            local ambiguous = (#parts_recipes > 1)

            for _, recipe in pairs(parts_recipes) do
                local parts_product = recipe.main_product  ---@cast parts_product -nil
                local disambiguator = (ambiguous) and ("-using-" .. recipe.name) or ""
                local rocket_parts_ingredient = {type="item", name=parts_product.name,
                amount=proto.rocket_parts_required}  ---@as Ingredient

                -- Mark rocket part items so item generation can make them non-hidden
                rocket_parts[parts_product.name] = true

                -- Add rocket launch product recipes
                if not proto.launch_to_space_platforms then
                    for item_name, products in pairs(launch_products) do
                        local main_product = prototypes.item[products[1].name]

                        local launch_recipe = custom_recipe()
                        launch_recipe.name = "impostor-launch-" .. item_name
                            .. "-from-" .. proto.name .. disambiguator
                        launch_recipe.factoriopedia_id = {type="entity", name=proto.name}
                        launch_recipe.localised_name = {"", main_product.localised_name, " ", {"fp.launch_recipe"}}
                        launch_recipe.sprite = "item/" .. main_product.name
                        launch_recipe.order = main_product.order
                        launch_recipe.categories = {["launch-rocket"] = true}
                        launch_recipe.energy = 1

                        local ingredients = {lib.flib.deep_copy(rocket_parts_ingredient),
                            {type="item", name=item_name, amount=1}}
                        generator.util.format_recipe(launch_recipe, products, products[1], ingredients)
                        -- Some items are only launched for their script effects, returning nothing
                        if next(launch_recipe.products) then insert_prototype(recipes, launch_recipe, nil) end
                    end
                end

                -- Add convenience recipe to build whole rocket instead of parts
                if script.feature_flags["space_travel"] then
                    local rocket_recipe = custom_recipe()
                    rocket_recipe.name = "impostor-" .. proto.name .. "-rocket" .. disambiguator
                    rocket_recipe.factoriopedia_id = {type="entity", name=proto.name}
                    rocket_recipe.localised_name = {"", proto.localised_name, " ", {"fp.launch_recipe"}}
                    rocket_recipe.sprite = "fp_silo_rocket"
                    rocket_recipe.order = recipe.order .. "-" .. proto.order
                    rocket_recipe.categories = {["launch-rocket"] = true}
                    rocket_recipe.energy = 1

                    local rocket_products = {{type="entity", name="custom-silo-rocket", amount=1}--[[@as Product]]}
                    local ingredients = {lib.flib.deep_copy(rocket_parts_ingredient)}
                    generator.util.format_recipe(rocket_recipe, rocket_products, rocket_products[1], ingredients)
                    insert_prototype(recipes, rocket_recipe, nil)
                end
            end

        elseif proto.type == "boiler" then
            -- Boilers that perform the same conversion use the same recipe, with
            --   one category for each boiler prototype.
            local category = "boiler-" .. proto.name

            for _, conversion in pairs(generator.util.get_boiler_conversions(proto)) do
                local input_proto, output_proto = conversion.input, conversion.output
                local name = table.concat({"impostor-boil", input_proto.name,
                    conversion.minimum_temperature, conversion.maximum_temperature,
                    output_proto.name, conversion.goal_temperature}, "-")
                local boiler_recipe = boiler_recipes[name]

                if boiler_recipe == nil then
                    boiler_recipe = custom_recipe()
                    boiler_recipe.name = name
                    boiler_recipe.factoriopedia_id = {type="fluid", name=output_proto.name}
                    boiler_recipe.localised_name = {"", input_proto.localised_name, " ", {"fp.boiling_recipe"}}
                    boiler_recipe.sprite = "fluid/" .. output_proto.name
                    boiler_recipe.order = input_proto.order .. "-" .. output_proto.order
                    boiler_recipe.categories = {}
                    boiler_recipe.energy = 1  -- treated separately by solver anyways
                    boiler_recipe.heat_capacity = input_proto.heat_capacity

                    local ingredients = {{type="fluid", name=input_proto.name, amount=1,
                        minimum_temperature=conversion.minimum_temperature,
                        maximum_temperature=conversion.maximum_temperature}}
                    -- Heating in place leaves the fluid alone, which this ratio comes out at 1 for
                    local amount = input_proto.heat_capacity / output_proto.heat_capacity
                    local products = {{type="fluid", name=output_proto.name,
                        temperature=conversion.goal_temperature, amount=amount}--[[@as Product]]}

                    generator.util.format_recipe(boiler_recipe, products, products[1], ingredients)

                    boiler_recipes[name] = boiler_recipe
                    insert_prototype(recipes, boiler_recipe, nil)
                end

                boiler_recipe.categories[category] = true
            end
        end
    end

    -- Add offshore pump recipes based on fluid tiles
    local pumped_fluids = {}
    for _, proto in pairs(prototypes.tile) do
        if proto.fluid and not pumped_fluids[proto.fluid.name] and not proto.hidden then
            local fluid = proto.fluid  ---@cast fluid -nil
            pumped_fluids[fluid.name] = true

            -- Note the tile so item generation can create its custom item
            table.insert(pumped_tiles, proto)

            local recipe = custom_recipe()
            recipe.name = "impostor-" .. fluid.name .. "-tile"
            recipe.factoriopedia_id = {type="tile", name=proto.name}
            recipe.localised_name = {"", fluid.localised_name, " ", {"fp.pumping_recipe"}}
            recipe.sprite = "fluid/" .. fluid.name
            recipe.order = proto.order
            recipe.categories = {["offshore-pump"] = true}
            recipe.energy = 1
            recipe.location_restricted = true

            local products = {{type="fluid", name=fluid.name, amount=60,
                temperature=fluid.default_temperature}--[[@as Product]]}
            local ingredients = {{type="entity", name="custom-" .. proto.name, amount=60}--[[@as Ingredient]]}
            generator.util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)
        end
    end

    -- Add purposeful spoiling recipes
    for _, proto in pairs(prototypes.item) do
        if proto.get_spoil_ticks() > 0 and proto.spoil_result then
            local recipe = custom_recipe()
            recipe.name = "impostor-spoiling-" .. proto.name
            recipe.factoriopedia_id = {type="item", name=proto.name}
            recipe.localised_name = {"", proto.spoil_result.localised_name, " ", {"fp.spoiling_recipe"}}
            recipe.sprite = "item/" .. proto.spoil_result.name
            recipe.order = proto.spoil_result.order
            recipe.categories = {["purposeful-spoiling"] = true}
            recipe.energy = proto.get_spoil_ticks() / 60 / proto.stack_size

            local products = {{type="item", name=proto.spoil_result.name, amount=1}--[[@as Product]]}
            local ingredients = {{type="item", name=proto.name, amount=1}--[[@as Ingredient]]}
            generator.util.format_recipe(recipe, products, products[1], ingredients)

            insert_prototype(recipes, recipe, nil)
        end
    end

    -- Add the recipe that power generating machines run. There is only one of it, since what
    -- differs between those machines is their fuel, which is configured on the machine itself.
    if first_generator ~= nil then
        local electricity_recipe = custom_recipe()
        electricity_recipe.name = "impostor-electricity"
        -- No single entity defines this, so just pick the first one for Factoriopedia
        electricity_recipe.factoriopedia_id = {type="entity", name=first_generator}
        electricity_recipe.localised_name = {"fp.electric_power"}
        electricity_recipe.sprite = "fp_electric_power"
        electricity_recipe.order = "z-a"
        electricity_recipe.categories = {["electricity"] = true}
        -- An energy of 1J means a machine speed given in watts yields that many joules per second
        electricity_recipe.energy = 1

        local products = {{type="entity", name="custom-electric-power", amount=1}--[[@as Product]]}
        generator.util.format_recipe(electricity_recipe, products, products[1], {})
        insert_prototype(recipes, electricity_recipe, nil)
    end

    return recipes
end

---@param recipes NamedPrototypes<FPRecipePrototype>
function generator.recipes.second_pass(recipes)
    local machines = storage.prototypes.machines
    for _, recipe in pairs(recipes) do
        -- Check if recipes have a machine to produce them
        if not machines[recipe.combined_category] then
            remove_prototype(recipes, recipe.name, nil)
        -- Give custom recipes a tooltip after items have been generated
        elseif recipe.custom then
            recipe.tooltip = generator.util.recipe_tooltip(recipe)
        end
    end
end


---@class FPItemPrototype: FPPrototypeWithCategory
---@field data_type "items"
---@field type "item" | "fluid" | "entity"
---@field hidden boolean
---@field stack_size uint?
---@field weight double?
---@field temperature float?
---@field base_name string?
---@field ingredient_only boolean
---@field order string
---@field group ItemGroup
---@field subgroup ItemGroup
---@field tooltip LocalisedString?
---@field fixed_unit LocalisedString?
---@field special boolean

---@alias RelevantItems table<ItemType, table<ItemName, ItemDetails>>

---@class ItemDetails
---@field ingredient_only boolean
---@field temperature float?

---@class CustomItemDetails
---@field name string
---@field localised_name LocalisedString
---@field sprite SpritePath
---@field hidden boolean
---@field order string
---@field special boolean?
---@field fixed_unit LocalisedString|nil
---@field group ItemGroup?
---@field subgroup ItemGroup?

---@return NamedPrototypesWithCategory<FPItemPrototype>
function generator.items.generate()
    local items = {}   ---@type NamedPrototypesWithCategory<FPItemPrototype>

    local recipe_prototypes = storage.prototypes.recipes  ---@as NamedPrototypes<FPRecipePrototype>

    -- Build custom items, representing in-world entities mostly
    local custom_items = {}  ---@type NamedPrototypes<CustomItemDetails>

    -- Deposits and lakes match the entities/tiles that recipe generation created recipes for
    for _, proto in pairs(resource_deposits) do
        local item_name = "custom-" .. proto.name
        custom_items[item_name] = {
            name = item_name,
            localised_name = {"", proto.localised_name, " ", {"fp.deposit"}},
            sprite = "entity/" .. proto.name,
            hidden = true,
            order = proto.order
        }
        generator.util.add_default_groups(custom_items[item_name])
    end

    for _, proto in pairs(pumped_tiles) do
        local item_name = "custom-" .. proto.name
        custom_items[item_name] = {
            name = item_name,
            localised_name = {"", proto.localised_name, " ", {"fp.lake"}},
            sprite = "tile/" .. proto.name,
            hidden = true,
            order = proto.order
        }
        generator.util.add_default_groups(custom_items[item_name])
    end

    if script.feature_flags["space_travel"] then
        -- Only need one rocket item for all silos/recipes
        local rocket_recipe = {
            name = "custom-silo-rocket",
            localised_name = {"", {"entity-name.rocket"}, " ", {"fp.launch_recipe"}},
            sprite = "fp_silo_rocket",
            hidden = false,
            order = "z-a"
        }
        local vanilla_parts_recipe = prototypes.recipe["rocket-part"]
        if vanilla_parts_recipe then  -- make it nicer for vanilla at least
            rocket_recipe.group = generator.util.generate_group_table(vanilla_parts_recipe.group)
            rocket_recipe.subgroup = generator.util.generate_group_table(vanilla_parts_recipe.subgroup)
        else
            generator.util.add_default_groups(rocket_recipe)
        end
        custom_items["custom-silo-rocket"] = rocket_recipe
    end

    custom_items["custom-agriculture-square"] = {
        name = "custom-agriculture-square",
        localised_name = {"fp.agriculture_square"},
        sprite = "fp_agriculture_square",
        hidden = true,
        order = "z-b",
        fixed_unit = {"fp.agriculture_unit"}
    }
    generator.util.add_default_groups(custom_items["custom-agriculture-square"])

    local electric_power = {
        name = "custom-electric-power",
        localised_name = {"fp.electric_power"},
        sprite = "fp_electric_power",
        hidden = false,
        order = "z-c1",
        special = true
    }
    local electricity_recipe = recipe_prototypes["impostor-electricity"]
    local factoriopedia_id = (electricity_recipe) and electricity_recipe.factoriopedia_id or nil
    generator.util.add_entity_groups(electric_power, (factoriopedia_id) and factoriopedia_id.name or nil)
    custom_items["custom-electric-power"] = electric_power

    custom_items["custom-heat-power"] = {
        name = "custom-heat-power",
        localised_name = {"fp.heat_power"},
        sprite = "fp_heat_power",
        hidden = true,
        order = "z-c2",
        special = true
    }
    generator.util.add_default_groups(custom_items["custom-heat-power"])

    custom_items["custom-heating-power"] = {
        name = "custom-heating-power",
        localised_name = {"fp.heating_power"},
        sprite = "fp_heating_power",
        hidden = true,
        order = "z-c3",
        special = true
    }
    generator.util.add_default_groups(custom_items["custom-heating-power"])

    local relevant_items = {item={}, fluid={}, entity={}}
    local fluid_has_temperature = {}
    -- Extract items from recipes and note whether they are ever used as a product
    for _, recipe_proto in pairs(recipe_prototypes) do
        for _, item_category in pairs({"products", "ingredients"}) do
            for _, item_data in pairs(recipe_proto[item_category]) do
                local type_data = relevant_items[item_data.type]

                if type_data[item_data.name] == nil then
                    type_data[item_data.name] = {
                        ingredient_only = true,
                        temperature = item_data.temperature,
                        base_name = item_data.base_name
                    }
                end

                if item_category == "products" then
                    type_data[item_data.name].ingredient_only = false
                end

                if item_data.type == "fluid" then
                    if item_data.temperature then
                        fluid_has_temperature[item_data.base_name] = true
                    else
                        fluid_has_temperature[item_data.name] = fluid_has_temperature[item_data.name] or false
                    end
                end
            end
        end
    end

    -- Add a default_temperature version for fluids that don't have any
    for name, exists in pairs(fluid_has_temperature) do
        if not exists then
            local temperature = prototypes.fluid[name].default_temperature
            relevant_items["fluid"][lib.temperature.name_with(name, temperature)] = {
                ingredient_only = true,
                temperature = temperature,
                base_name = name
            }
        end
    end

    -- Add a custom item for each kind of pollution
    for _, pollutant in pairs(prototypes.airborne_pollutant) do
        local item_name = "custom-" .. pollutant.name
        custom_items[item_name] = {
            name = item_name,
            localised_name = {"", pollutant.localised_name},
            sprite = "fp_emissions",
            hidden = true,
            order = "z-c3-" .. pollutant.order,
            special = true
        }
        generator.util.add_default_groups(custom_items[item_name])
        relevant_items["entity"][item_name] = {ingredient_only=true}
    end

    -- Electricity is normally produced by generators, add manually otherwise
    relevant_items["entity"]["custom-electric-power"] =
        relevant_items["entity"]["custom-electric-power"] or {ingredient_only=true}

    -- No recipes use these (yet) so they need to be added manually
    relevant_items["entity"]["custom-heat-power"] = {ingredient_only=true}
    relevant_items["entity"]["custom-heating-power"] = {ingredient_only=true}

    for type, item_table in pairs(relevant_items) do
        for item_name, item_details in pairs(item_table) do
            local proto_name = item_details.base_name or item_name
            local proto = (type == "entity") and custom_items[proto_name] or
                prototypes[type][proto_name]

            local item = {
                name = item_name,
                localised_name = proto.localised_name,
                sprite = (type .. "/" .. proto.name),
                type = type,
                hidden = (not rocket_parts[item_name]) and proto.hidden,
                stack_size = (type == "item") and proto.stack_size or nil,
                weight = (type == "item") and proto.weight or nil,
                temperature = item_details.temperature,
                base_name = item_details.base_name,
                ingredient_only = item_details.ingredient_only,
                order = proto.order,
                group = generator.util.generate_group_table(proto.group--[[@cast -nil]]),
                subgroup = generator.util.generate_group_table(proto.subgroup--[[@cast -nil]])
            }

            if type == "entity" then
                item.sprite = proto.sprite
                item.group = proto.group
                item.subgroup = proto.subgroup
                item.tooltip = proto.localised_name
                item.fixed_unit = proto.fixed_unit -- can be nil
                item.special = proto.special or false
            elseif type == "fluid" and item.temperature then
                item.localised_name = {"fp.fluid_with_temperature", proto.localised_name, item.temperature}
                item.tooltip = item.localised_name
            end

            insert_prototype(items, item--[[@as FPPrototype]], item.type)
        end
    end

    return items
end


---@class FPMachinePrototype: FPPrototypeWithCategory
---@field data_type "machines"
---@field category string
---@field combined_category string
---@field elem_type ElemType
---@field prototype_category PrototypeCategory?
---@field ingredient_limit integer
---@field product_limit integer
---@field fluid_channels FluidChannels
---@field speed double
---@field crafting_speed_quality_multiplier table<QualityID, double>
---@field energy_type "burner" | "electric" | "heat" | "void"
---@field energy_usage double
---@field energy_drain double
---@field quality_affects_energy_usage boolean?
---@field energy_usage_quality_multiplier table<QualityID, double>
---@field emissions_per_joule EmissionsMap
---@field emissions_per_second EmissionsMap
---@field burner MachineBurner?
---@field built_by_item_name string?
---@field effect_receiver FormattedEffectReceiver
---@field allowed_effects AllowedEffects?
---@field allowed_module_categories table<string, boolean>?
---@field module_limit uint16
---@field quality_affects_module_slots boolean?
---@field module_slots_quality_bonus table<QualityID, uint16>
---@field surface_conditions SurfaceCondition[]
---@field resource_drain_rate number?
---@field uses_force_mining_productivity_bonus boolean?
---@field heating_energy double

---@class FluidChannels
---@field input integer
---@field output integer

---@class MachineBurner
---@field effectivity double
---@field categories table<string, boolean>
---@field combined_category string
---@field produces_spent_fluid boolean?
---@field spent_fluid SpentFluidSpecification?
---@field fluid_usage_per_tick double?
---@field scale_fluid_usage boolean?
---@field burns_fluid boolean?
---@field fluid_filter string?
---@field minimum_temperature float?
---@field maximum_temperature float?

---@alias EmissionsMap table<string, double>
---@alias PrototypeCategory ("crafter" | "launcher" | "mining_drill" | "boiler" | "offshore_pump" | "generator")

---@return NamedPrototypesWithCategory<FPMachinePrototype>
function generator.machines.generate()
    local machines = {}  ---@type NamedPrototypesWithCategory<FPMachinePrototype>
    local machine_categories = {}  -- temporary list to be combined later

    local used_category_names = {}  ---@type table<string, boolean>
    for _, recipe_proto in pairs(storage.prototypes.recipes) do
        for category, _ in pairs(recipe_proto.categories) do
            used_category_names[category] = true
        end
    end

    ---@param burns_fluid boolean
    ---@param fluid_box LuaFluidBoxPrototype
    ---@return string
    local function fluid_fuel_category(burns_fluid, fluid_box)
        local fuel_category = (burns_fluid) and "fluid-fuel" or "fluid-heat"
        if fluid_box.filter then fuel_category = fuel_category .. "-filter-" .. fluid_box.filter.name end
        return fuel_category
    end

    -- A generator's boxes are plain entity ones, so unlike a fluid energy source it doesn't
    -- expose them separately and they have to be picked out by their production type
    ---@param proto LuaEntityPrototype
    ---@return LuaFluidBoxPrototype? input
    ---@return LuaFluidBoxPrototype? output
    local function generator_fluid_boxes(proto)
        local input, output = nil, nil
        for _, fluid_box in pairs(proto.fluidbox_prototypes) do
            if fluid_box.production_type == "output" then output = output or fluid_box
            else input = input or fluid_box end
        end
        return input, output
    end

    ---@param category string
    ---@param proto LuaEntityPrototype
    ---@param prototype_category PrototypeCategory?
    ---@return FPMachinePrototype?
    local function generate_category_entry(category, proto, prototype_category)
        -- If no recipe uses this machine's category, it is pointless
        if used_category_names[category] == nil then return end
        -- First, determine if there is a valid sprite for this machine
        local sprite = generator.util.determine_entity_sprite(proto)
        if sprite == nil then return end

        -- Determine data related to the energy source
        local energy_type, emissions_per_joule = "", {}  -- no emissions if no energy source is present
        local burner = nil  ---@type MachineBurner?

        local energy_usage  ---@type number
        if prototype_category == "generator" then
            -- For these machines this is the power they put out, not what they consume. It can't
            -- come from get_max_energy_usage(), which reports a burner generator's fuel consumption,
            -- ie. its output divided by its effectivity.
            energy_usage = generator.util.get_base_value(proto.get_max_energy_production()) or 0
        else
            local max_usage = generator.util.get_base_value(proto.get_max_energy_usage())
            energy_usage = proto.energy_usage or max_usage or 0
        end
        local energy_drain = 0.0

        -- Determine the item that actually builds this machine for the item requester
        -- There can technically be more than one, but bots use the first one, so I do too
        local built_by_item_name = (proto.items_to_place_this) and
            proto.items_to_place_this[1]--[[@cast -nil]].name or nil

        local burner_prototype = proto.burner_prototype
        local fluid_burner_prototype = proto.fluid_energy_source_prototype
        -- Only plain generators feed on a fluid box of their own; burner generators use a real burner
        local generator_fluid_box, generator_output_box = nil, nil
        if proto.type == "generator" then generator_fluid_box, generator_output_box = generator_fluid_boxes(proto) end

        -- Determine the details of this entity's energy source
        if generator_fluid_box then
            -- A generator's electric source is its output, so it's the fluid box that acts as its
            -- energy source. It carries the same fields a fluid energy source does, so it maps
            -- onto a burner in the same way, just with the resulting energy flowing outwards.
            energy_type = "burner"
            local electric_source = proto.electric_energy_source_prototype  ---@cast electric_source -nil
            emissions_per_joule = electric_source.emissions_per_joule

            local burns_fluid = proto.burns_fluid or false
            burner = {
                effectivity = proto.effectivity or 1,
                categories = {[fluid_fuel_category(burns_fluid, generator_fluid_box)] = true},
                combined_category = "",  -- filled in by fuel generator
                -- An output box without a spent_fluid falls back to the input fluid's own one
                produces_spent_fluid = (generator_output_box ~= nil),
                spent_fluid = proto.spent_fluid,
                fluid_usage_per_tick = generator.util.get_base_value(proto.get_fluid_usage_per_tick()),
                scale_fluid_usage = proto.scale_fluid_usage,
                burns_fluid = burns_fluid,
                fluid_filter = (generator_fluid_box.filter) and generator_fluid_box.filter.name or nil,
                -- Deliberately not proto.maximum_temperature: a generator clamps the energy it
                -- extracts rather than refusing hotter fluid, which is what wasted_share models
                minimum_temperature = generator_fluid_box.minimum_temperature,
                maximum_temperature = generator_fluid_box.maximum_temperature
            }

        elseif burner_prototype then
            energy_type = "burner"
            emissions_per_joule = burner_prototype.emissions_per_joule
            burner = {
                effectivity = burner_prototype.effectivity,
                categories = burner_prototype.fuel_categories,
                combined_category = ""  -- filled in by fuel generator
            }

        elseif fluid_burner_prototype then
            energy_type = "burner"
            emissions_per_joule = fluid_burner_prototype.emissions_per_joule

            local fluid_box = fluid_burner_prototype.fluid_box
            burner = {
                effectivity = fluid_burner_prototype.effectivity,
                categories = {[fluid_fuel_category(fluid_burner_prototype.burns_fluid, fluid_box)] = true},
                combined_category = "",  -- filled in by fuel generator
                produces_spent_fluid = (fluid_burner_prototype.output_fluid_box ~= nil),
                spent_fluid = fluid_burner_prototype.spent_fluid,
                -- A zero usage means the source doesn't cap its own consumption
                fluid_usage_per_tick = (fluid_burner_prototype.fluid_usage_per_tick > 0)
                    and fluid_burner_prototype.fluid_usage_per_tick or nil,
                scale_fluid_usage = fluid_burner_prototype.scale_fluid_usage,
                -- burns_fluid == true uses the fluid's fuel_value, otherwise its heat above the default temperature
                burns_fluid = fluid_burner_prototype.burns_fluid,
                fluid_filter = (fluid_box.filter) and fluid_box.filter.name or nil,
                minimum_temperature = fluid_box.minimum_temperature,
                maximum_temperature = fluid_box.maximum_temperature
            }

        elseif proto.electric_energy_source_prototype then
            energy_type = "electric"
            energy_drain = proto.electric_energy_source_prototype.drain
            emissions_per_joule = proto.electric_energy_source_prototype.emissions_per_joule

        elseif proto.heat_energy_source_prototype then
            energy_type = "heat"
            emissions_per_joule = proto.heat_energy_source_prototype.emissions_per_joule

        elseif proto.void_energy_source_prototype then
            energy_type = "void"
            emissions_per_joule = proto.void_energy_source_prototype.emissions_per_joule
        end

        -- Determine fluid input/output channels
        local input_channels, output_channels = 0, 0  ---@type integer, integer
        for _, fluidbox in pairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" then
                output_channels = output_channels + 1
            else  -- "input" and "input-output"
                input_channels = input_channels + 1
            end
        end

        if generator_fluid_box then
            input_channels = input_channels - 1
            if generator_output_box then output_channels = output_channels - 1 end
        elseif fluid_burner_prototype then
            input_channels = input_channels - 1
            if fluid_burner_prototype.output_fluid_box then output_channels = output_channels - 1 end
        end

        return {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = sprite,
            category = category,
            combined_category = nil,  -- set after all machines are generated
            elem_type = "entity",
            prototype_category = prototype_category,
            ingredient_limit = (proto.ingredient_count or 255),
            product_limit = (proto.max_item_product_count or 255),
            fluid_channels = {input = input_channels, output = output_channels},
            speed = generator.util.get_base_value(proto.get_crafting_speed()),
            crafting_speed_quality_multiplier = proto.crafting_speed_quality_multiplier,
            energy_type = energy_type,
            energy_usage = energy_usage,
            energy_drain = energy_drain,
            quality_affects_energy_usage = proto.quality_affects_energy_usage,  -- can be nil
            energy_usage_quality_multiplier = proto.energy_usage_quality_multiplier,
            emissions_per_joule = emissions_per_joule,
            emissions_per_second = proto.emissions_per_second or {},
            burner = burner,
            built_by_item_name = built_by_item_name,
            effect_receiver = generator.util.format_effect_receiver(proto),
            allowed_effects = proto.allowed_effects,  -- can be nil
            allowed_module_categories = proto.allowed_module_categories,  -- can be nil
            module_limit = (proto.module_inventory_size or 0),
            quality_affects_module_slots = proto.quality_affects_module_slots,  -- can be nil
            module_slots_quality_bonus = proto.module_slots_quality_bonus,
            surface_conditions = proto.surface_conditions,
            uses_force_mining_productivity_bonus = proto.uses_force_mining_productivity_bonus,
            heating_energy = proto.heating_energy * 60
        }  ---@as FPMachinePrototype
    end

    ---@param machine FPMachinePrototype
    local function insert_machine(machine)
        machine_categories[machine.category] = machine_categories[machine.category] or {}
        table.insert(machine_categories[machine.category], machine)
    end

    local recipe_prototypes = storage.prototypes.recipes  ---@as NamedPrototypes<FPRecipePrototype>

    local entity_filter = {{filter="hidden", invert=true}}
    for _, proto in pairs(prototypes.get_entity_filtered(entity_filter)) do
        if proto.crafting_categories and proto.energy_usage ~= nil then
            -- Silo launch recipes use a separate machine
            if proto.type == "rocket-silo" then
                local machine = generate_category_entry("launch-rocket", proto, "launcher")
                if machine then
                    -- speed and energy_usage will be wrong here, but are determined
                    -- dynamically later on depending on quality

                    machine.built_by_item_name = nil
                    machine.effect_receiver = generator.util.format_effect_receiver()
                    machine.allowed_effects = nil
                    machine.module_limit = 0

                    insert_machine(machine)
                end
            end  -- silos are also added as normal machines to produce rocket parts

            if proto.fixed_recipe then  -- fixed recipe machines get their own category
                if recipe_prototypes[proto.fixed_recipe.name] ~= nil then
                    local category = proto.name .. "-using-" .. proto.fixed_recipe.name
                    local machine = generate_category_entry(category, proto, "crafter")
                    if machine then insert_machine(machine) end
                end
            else  -- otherwise add machines as normal
                for category, _ in pairs(proto.crafting_categories) do
                    local machine = generate_category_entry(category, proto, "crafter")
                    if machine then insert_machine(machine) end
                end
            end


        elseif proto.type == "mining-drill" then
            for category, _ in pairs(proto.resource_categories--[[@cast -nil]]) do
                local machine = generate_category_entry(category, proto, "mining_drill")
                if machine then
                    machine.speed = proto.mining_speed
                    machine.resource_drain_rate = proto.resource_drain_rate_percent--[[@cast -nil]] / 100
                    insert_machine(machine)
                end
            end

        elseif proto.type == "boiler" then
            -- Every boiler is its own category, assigned to the recipes that can use it
            local machine = generate_category_entry("boiler-" .. proto.name, proto, "boiler")
            if machine then
                machine.speed = machine.energy_usage * 60
                insert_machine(machine)
            end

        elseif proto.type == "offshore-pump" then
            local fluid_box = proto.fluidbox_prototypes[1]
            local fixed_fluid = (fluid_box and fluid_box.filter) and fluid_box.filter.name or nil
            local category = (fixed_fluid) and ("offshore-pump-" .. fixed_fluid) or "offshore-pump"
            local machine = generate_category_entry(category, proto, "offshore_pump")
            if machine then
                machine.speed = generator.util.get_base_value(proto.get_pumping_speed())
                insert_machine(machine)
            end

        elseif proto.type == "agricultural-tower" then
            local machine = generate_category_entry(proto.type, proto, nil)
            if machine then
                local radius = proto.agricultural_tower_radius  ---@cast radius -nil
                local crane_energy_usage = proto.crane_energy_usage  ---@cast crane_energy_usage -nil
                -- One plant per grid square, with the tower occupying the center square
                machine.speed = ((2 * radius + 1) ^ 2) - 1
                -- The crane of a fully utilized tower is moving near-constantly, so include its usage
                machine.energy_usage = machine.energy_usage + crane_energy_usage
                -- Agri tower silently drops any fluid ingredients/products, so just allow them
                machine.fluid_channels = {input = 255, output = 255}
                insert_machine(machine)
            end

        elseif proto.type == "container" then
            local machine = generate_category_entry("purposeful-spoiling", proto, nil)
            if machine then
                machine.speed = proto.get_inventory_size(defines.inventory.chest) or 1
                machine.energy_usage = 0
                insert_machine(machine)
            end

        elseif proto.type == "generator" or proto.type == "burner-generator" then
            local machine = generate_category_entry("electricity", proto, "generator")
            if machine then
                -- Speed in watts combines with the recipe energy of 1J to produce
                --   that many joules of power per second
                machine.speed = machine.energy_usage * 60
                insert_machine(machine)
            end
        end
    end

    -- Create category for each combination of machines used by recipes
    local combined_list = {}  -- set of every possible combined_category
    for _, recipe_proto in pairs(recipe_prototypes) do
        -- This removes invalid machine categories and sets the combined category
        generator.util.format_category_data(recipe_proto, combined_list, machine_categories)

        if recipe_proto.combined_category == "" then
            -- An empty combined category means no valid machines, so remove this recipe
            remove_prototype(recipe_prototypes, recipe_proto.name, nil)
        end
    end

    -- Fill machine list, implicitly dropping machines that aren't used by any recipe
    generator.util.fill_categories(combined_list, machine_categories, machines, insert_prototype)

    return machines
end

---@param a FPMachinePrototype
---@param b FPMachinePrototype
---@return boolean
function generator.machines.sorting_function(a, b)
    if a.speed < b.speed then return true
    elseif a.speed > b.speed then return false end
    return false
end


---@class FPFuelPrototype: FPPrototypeWithCategory
---@field data_type "fuels"
---@field type "item" | "fluid"
---@field category string
---@field combined_category string
---@field elem_type ElemType
---@field fuel_value float
---@field emissions_multiplier double

---@class FPItemFuelPrototype: FPFuelPrototype
---@field type "item"
---@field burnt_result string?
---@field stack_size uint?
---@field weight double?

---@class FPFluidFuelPrototype: FPFuelPrototype
---@field type "fluid"
---@field minimum_temperature float?
---@field exclusive_minimum boolean?
---@field spent_fluid SpentFluidSpecification?
---@field heat_capacity double?
---@field default_temperature float?

---@alias AnyFPFuelPrototype FPItemFuelPrototype | FPFluidFuelPrototype

---@return NamedPrototypesWithCategory<FPFuelPrototype>
function generator.fuels.generate()
    local fuels = {}  ---@type NamedPrototypesWithCategory<FPFuelPrototype>
    local fuel_categories = {}  -- temporary list to be combined later

    local fuel_filter = {{filter="fuel-value", comparison=">", value=0},
        {filter="fuel-value", comparison="<", value=1e+21, mode="and"},
        {filter="hidden", invert=true, mode="and"}}

    -- Build solid fuels - to be combined into categories afterwards
    local item_list = generator.util.get_item_members("item")
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
                combined_category = nil,  -- set below
                fuel_value = proto.fuel_value,
                emissions_multiplier = proto.fuel_emissions_multiplier,
                stack_size = proto.stack_size,
                weight = proto.weight,
                burnt_result = (proto.burnt_result) and proto.burnt_result.name or nil
                -- burnt_result item not explicitly added as FPItemPrototype, relies on mod to use it elsewhere
            }
            fuel_categories[fuel.category] = fuel_categories[fuel.category] or {}
            table.insert(fuel_categories[fuel.category], fuel)
        end
    end

    -- Add fluid fuels - which fluids are valid depends on the fluid energy source that wants them,
    -- so only the categories that machines actually asked for are generated
    local fluid_list = generator.util.get_item_members("fluid")

    -- Note which fluids exist above their default temperature, ie. can carry any usable heat at all
    local heated_fluids = {}  ---@type table<string, boolean>
    for _, item in pairs(fluid_list) do
        if item.base_name and item.temperature > prototypes.fluid[item.base_name].default_temperature then
            heated_fluids[item.base_name] = true
        end
    end

    local machine_prototypes = storage.prototypes.machines  ---@as NamedPrototypesWithCategory<FPMachinePrototype>

    -- Collect the fluid fuel categories machines ask for, keeping their burner around, as a
    -- category name doesn't say which fluids fit it
    local requested_categories = {}  ---@type table<string, MachineBurner>
    for _, machine_category in pairs(machine_prototypes) do
        for _, machine_proto in pairs(machine_category.members) do
            local burner = machine_proto.burner
            if burner and burner.burns_fluid ~= nil then
                for category, _ in pairs(burner.categories) do
                    requested_categories[category] = burner
                end
            end
        end
    end

    -- Burning uses the fuel value, so only fluids that have one qualify. Otherwise energy comes from
    -- the fluid's heat, which any fluid that can be heated up at all can provide.
    local burnable_fluids = prototypes.get_fluid_filtered(fuel_filter)
    local heatable_fluids = prototypes.get_fluid_filtered{{filter="hidden", invert=true}}

    for category, burner in pairs(requested_categories) do
        local burns_fluid, filter_name = burner.burns_fluid, burner.fluid_filter

        local relevant_fluids = (burns_fluid) and burnable_fluids or heatable_fluids
        for _, proto in pairs(relevant_fluids) do
            local usable = (burns_fluid) and (fluid_list[proto.name] ~= nil)
                or ((heated_fluids[proto.name] ~= nil) and proto.heat_capacity > 0)

            if usable and (filter_name == nil or filter_name == proto.name) then
                local fuel = {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = "fluid/" .. proto.name,
                    type = "fluid",
                    elem_type = "fluid",
                    category = category,
                    combined_category = nil,  -- set below
                    fuel_value = (burns_fluid) and proto.fuel_value or 0,
                    emissions_multiplier = proto.emissions_multiplier,
                    spent_fluid = proto.spent_fluid  -- can be nil
                    -- spent_fluid not explicitly added as FPItemPrototype, relies on mod to use it elsewhere
                }

                if not burns_fluid then
                    fuel.heat_capacity = proto.heat_capacity
                    fuel.default_temperature = proto.default_temperature
                    fuel.minimum_temperature = proto.default_temperature
                    fuel.exclusive_minimum = true
                end

                fuel_categories[category] = fuel_categories[category] or {}
                table.insert(fuel_categories[category], fuel)
            end
        end
    end

    local combined_list = {}  -- set of every possible combined_category

    -- Create category for each combination of fuels used by machines
    for _, machine_category in pairs(machine_prototypes) do
        for _, machine_proto in pairs(machine_category.members) do
            if machine_proto.energy_type == "burner" then  ---@cast machine_proto.burner -nil
                -- This removes invalid fuel categories and sets the combined category
                generator.util.format_category_data(machine_proto.burner, combined_list, fuel_categories)

                if machine_proto.burner.combined_category == "" then
                    -- An empty combined category means no valid fuels, so remove this machine
                    remove_prototype(machine_prototypes, machine_proto.name, machine_category.name)
                end
            end
        end
    end

    -- Fill fuel list, implicitly dropping fuels that aren't used by any machine
    generator.util.fill_categories(combined_list, fuel_categories, fuels, insert_prototype)

    return fuels
end

---@param a FPFuelPrototype
---@param b FPFuelPrototype
---@return boolean
function generator.fuels.sorting_function(a, b)
    local a_capacity = a--[[@as FPFluidFuelPrototype]].heat_capacity or 0
    local b_capacity = b--[[@as FPFluidFuelPrototype]].heat_capacity or 0

    if a.fuel_value < b.fuel_value then return true
    elseif a.fuel_value > b.fuel_value then return false
    elseif a_capacity < b_capacity then return true
    elseif a_capacity > b_capacity then return false end
    return false
end


---@class FPBeltPrototype: FPPrototype
---@field data_type "belts"
---@field elem_type ElemType
---@field rich_text string
---@field throughput double

---@return NamedPrototypes<FPBeltPrototype>
function generator.belts.generate()
    local belts = {} ---@type NamedPrototypes<FPBeltPrototype>

    local belt_filter = {{filter="type", type="transport-belt"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(belt_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        if sprite ~= nil then
            ---@diagnostic disable-next-line: missing-fields
            local belt = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                throughput = proto.belt_speed--[[@cast -nil]] * 480
            }  ---@type FPBeltPrototype
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


---@class FPPumpPrototype: FPPrototype
---@field data_type "pumps"
---@field elem_type ElemType
---@field rich_text string
---@field pumping_speed double

---@return NamedPrototypes<FPPumpPrototype>
function generator.pumps.generate()
    local pumps = {} ---@type NamedPrototypes<FPPumpPrototype>

    local pump_filter = {{filter="type", type="pump"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(pump_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        if sprite ~= nil then
            ---@diagnostic disable-next-line: missing-fields
            local pump = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                pumping_speed = generator.util.get_base_value(proto.get_pumping_speed())--[[@cast -nil]] * 60
                -- pumping_speed is unused as the mod uses get_pumping_speed(quality)
            }  ---@type FPPumpPrototype
            insert_prototype(pumps, pump, nil)
        end
    end

    return pumps
end


---@class FPSiloPrototype: FPPrototype
---@field data_type "silos"
---@field elem_type ElemType
---@field rich_text string
---@field rocket_lift_weight double

---@return NamedPrototypes<FPSiloPrototype>
function generator.silos.generate()
    local silos = {} ---@type NamedPrototypes<FPSiloPrototype>

    local silo_filter = {{filter="type", type="rocket-silo"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(silo_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        if sprite ~= nil then
            ---@diagnostic disable-next-line: missing-fields
            local silo = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                rocket_lift_weight = proto.lift_weight  ---@as double
            }  ---@type FPSiloPrototype
            insert_prototype(silos, silo, nil)
        end
    end

    return silos
end


---@class FPWagonPrototype: FPPrototypeWithCategory
---@field data_type "wagons"
---@field category "cargo-wagon" | "fluid-wagon"
---@field elem_type ElemType
---@field rich_text string
---@field storage number

---@return NamedPrototypesWithCategory<FPWagonPrototype>
function generator.wagons.generate()
    local wagons = {}  ---@type NamedPrototypesWithCategory<FPWagonPrototype>

    -- Add cargo wagons
    local cargo_wagon_filter = {{filter="type", type="cargo-wagon"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(cargo_wagon_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        local inventory_size = proto.get_inventory_size(defines.inventory.cargo_wagon)  ---@as number
        if sprite ~= nil and inventory_size > 0 then
            ---@diagnostic disable-next-line: missing-fields
            local wagon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "cargo-wagon",
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                storage = inventory_size
                -- storage is unused as the mod uses get_inventory_size(quality)
            }  ---@type FPWagonPrototype
            insert_prototype(wagons, wagon, wagon.category)
        end
    end

    -- Add fluid wagons
    local fluid_wagon_filter = {{filter="type", type="fluid-wagon"},
        {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(fluid_wagon_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        if sprite ~= nil and proto.fluid_capacity > 0 then
            ---@diagnostic disable-next-line: missing-fields
            local wagon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "fluid-wagon",
                elem_type = "entity",
                rich_text = "[entity=" .. proto.name .. "]",
                storage = proto.fluid_capacity
                -- storage is unused as the mod uses get_fluid_capacity(quality)
            }  ---@type FPWagonPrototype
            insert_prototype(wagons, wagon, wagon.category)
        end
    end

    return wagons
end


---@class FPModulePrototype: FPPrototypeWithCategory
---@field data_type "modules"
---@field category string
---@field tier uint32
---@field effects IntegerModuleEffects
---@field quality_multipliers table<ModuleEffectName, float>

---@return NamedPrototypesWithCategory<FPModulePrototype>
function generator.modules.generate()
    local modules = {}  ---@type NamedPrototypesWithCategory<FPModulePrototype>

    local module_filter = {{filter="type", type="module"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_item_filtered(module_filter)) do
        local sprite = "item/" .. proto.name
        if helpers.is_valid_sprite_path(sprite) then
            ---@diagnostic disable-next-line: missing-fields
            local module = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = proto.category--[[@as string]],
                tier = proto.tier--[[@as uint32]],
                effects = generator.util.formatted_effects(proto.module_effects),
                quality_multipliers = {
                    consumption = proto.consumption_quality_multiplier--[[@as float]],
                    speed = proto.speed_quality_multiplier--[[@as float]],
                    productivity = proto.productivity_quality_multiplier--[[@as float]],
                    pollution = proto.pollution_quality_multiplier--[[@as float]],
                    quality = proto.quality_quality_multiplier--[[@as float]]
                }
            }  ---@type FPModulePrototype
            insert_prototype(modules, module, module.category)
        end
    end

    return modules
end

---@param a FPModulePrototype
---@param b FPModulePrototype
---@return boolean
function generator.modules.sorting_function(a, b)
    -- Sorting done so IDs can be used for order comparison
    if a.category < b.category then return true
    elseif a.category > b.category then return false
    elseif a.tier < b.tier then return true
    elseif a.tier > b.tier then return false end
    return false
end


---@class FPBeaconPrototype: FPPrototype
---@field data_type "beacons"
---@field category "beacon"
---@field elem_type ElemType
---@field prototype_category "beacon"
---@field built_by_item_name string?
---@field allowed_effects AllowedEffects?
---@field allowed_module_categories table<string, boolean>?
---@field module_limit uint16
---@field quality_affects_module_slots boolean
---@field effectivity double
---@field distribution_effectivity_bonus_per_quality_level double
---@field profile double[]
---@field energy_usage double

---@return NamedPrototypes<FPBeaconPrototype>
function generator.beacons.generate()
    local beacons = {}  ---@type NamedPrototypes<FPBeaconPrototype>

    local beacon_filter = {{filter="type", type="beacon"}, {filter="hidden", invert=true, mode="and"}}
    for _, proto in pairs(prototypes.get_entity_filtered(beacon_filter)) do
        local sprite = generator.util.determine_entity_sprite(proto)
        local any_effect_viable = generator.util.is_any_effect_viable(proto)
        if sprite ~= nil and any_effect_viable and proto.module_inventory_size > 0
                and proto.distribution_effectivity > 0 then
            local built_by_item_name = (proto.items_to_place_this) and
                proto.items_to_place_this[1]--[[@cast -nil]].name or nil

            local max_usage = generator.util.get_base_value(proto.get_max_energy_usage())
            local energy_usage = proto.energy_usage or max_usage or 0

            ---@diagnostic disable-next-line: missing-fields
            local beacon = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = sprite,
                category = "beacon",  -- custom category to be similar to machines
                elem_type = "entity",
                prototype_category = "beacon",
                built_by_item_name = built_by_item_name,
                allowed_effects = proto.allowed_effects,  -- can be nil
                allowed_module_categories = proto.allowed_module_categories,  -- can be nil
                module_limit = proto.module_inventory_size--[[@as uint16]],
                quality_affects_module_slots = proto.quality_affects_module_slots--[[@as boolean]],
                effectivity = proto.distribution_effectivity--[[@as double]],
                distribution_effectivity_bonus_per_quality_level =
                    proto.distribution_effectivity_bonus_per_quality_level--[[@as double]],
                profile = ((#proto.profile == 0) and {1} or proto.profile)--[[@as double[] ]],
                energy_usage = energy_usage
            }  ---@type FPBeaconPrototype
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
    elseif a.effectivity > b.effectivity then return false end
    return false
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
        if not proto.hidden then
            table.insert(properties, {
                name = proto.name,
                order = proto.order,
                localised_name = proto.localised_name,
                localised_unit_key = proto.localised_unit_key,
                default_value = proto.default_value,
                is_time = proto.is_time
            })
        end
    end

    table.sort(properties, property_sorting_function)
    return properties
end

---@class FPLocationPrototype: FPPrototype
---@field data_type "locations"
---@field tooltip LocalisedString
---@field surface_properties SurfaceProperties?
---@field pollutant_type string?
---@field resource_recipes table<string, true>?
---@field entities_require_heating boolean

---@alias SurfaceProperties table<string, double>

-- Generates a table containing all 'places' with surface_conditions, like planets and platforms
---@return NamedPrototypes<FPLocationPrototype>
function generator.locations.generate()
    local locations = {}  ---@type NamedPrototypes<FPLocationPrototype>

    local property_prototypes = generate_surface_properties()

    ---@param proto LuaSpaceLocationPrototype | LuaSurfacePrototype
    ---@param category string
    ---@return FPLocationPrototype? location_proto
    local function build_location(proto, category)
        if proto.hidden or not proto.surface_properties then return nil end

        local sprite = category .. "/" .. proto.name
        if not helpers.is_valid_sprite_path(sprite) then return nil end

        local surface_properties = {}
        local tooltip = {"", {"fp.tt_title", proto.localised_name}, "\n"}  ---@type LocalisedString
        local current_table, next_index = tooltip, 4
        local resource_recipes = {}  ---@type table<string, true>

        for _, property_proto in pairs(property_prototypes) do
            local value = proto.surface_properties[property_proto.name] or property_proto.default_value
            surface_properties[property_proto.name] = value

            local value_and_unit = {property_proto.localised_unit_key, value}  ---@type LocalisedString
            if property_proto.is_time then value_and_unit = lib.format.time(value) end

            current_table, next_index = lib.build_localised_string(
                {"fp.surface_property", property_proto.localised_name, value_and_unit}, current_table, next_index)
        end

        if category == "space-location" and proto.map_gen_settings and proto.map_gen_settings.autoplace_settings then
            -- Check for minable resources
            local entity_autoplace = proto.map_gen_settings.autoplace_settings.entity
            if entity_autoplace then
                for key, _ in pairs(entity_autoplace.settings or {}) do
                    if prototypes.entity[key] and prototypes.entity[key].type == "resource" then
                        local recipe_key = "impostor-" .. key
                        resource_recipes[recipe_key] = true
                    end
                end
            end

            local tile_autoplace = proto.map_gen_settings.autoplace_settings.tile
            if tile_autoplace then
                for key, _ in pairs(tile_autoplace.settings or {}) do
                    -- Check for fluid tiles that can be extracted with offshore pumps
                    if prototypes.tile[key] and prototypes.tile[key].fluid then
                        local recipe_key = "impostor-" .. prototypes.tile[key].fluid.name .. "-tile"
                        resource_recipes[recipe_key] = true
                    end

                    -- Check for natural tiles that plants can grow on
                    if tile_can_have_plant[key] then
                        for _, plant in pairs(tile_can_have_plant[key]) do
                            resource_recipes["impostor-" .. plant] = true
                        end
                    end
                end
            end
        end

        ---@diagnostic disable-next-line: missing-fields
        local location = {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = sprite,
            tooltip = tooltip,
            surface_properties = surface_properties,
            pollutant_type = (category == "space-location" and proto.pollutant_type)
                and proto.pollutant_type.name or nil,
            resource_recipes = resource_recipes,
            entities_require_heating = (category == "space-location" and proto.entities_require_heating or false)
        }  ---@type FPLocationPrototype
        return location
    end

    for _, proto in pairs(prototypes.space_location) do
        local location = build_location(proto, "space-location")
        if location then insert_prototype(locations, location, nil) end
    end

    for _, proto in pairs(prototypes.surface) do
        local location = build_location(proto, "surface")
        if location then insert_prototype(locations, location, nil) end
    end

    -- Add special location that has no restrictions
    if table_size(locations) > 1 then
        ---@diagnostic disable-next-line: missing-fields
        local universal_location = {
            name = "universal",
            localised_name = {"fp.universal_location"},
            sprite = "fp_universal_planet",
            tooltip = {"fp.universal_location_tt"},
            surface_properties = nil,  -- accepts all machines and recipes
            pollutant_type = nil,  -- no pollution produced
            resource_recipes = nil  -- no restrictions on mined resources
        }  ---@type FPLocationPrototype
        insert_prototype(locations, universal_location, nil)
    end

    return locations
end

---@class FPQualityPrototype: FPPrototype
---@field data_type "qualities"
---@field rich_text LocalisedString
---@field always_show boolean
---@field level uint32
---@field default_multiplier double
---@field beacon_power_usage_multiplier double
---@field mining_drill_resource_drain_multiplier double
---@field beacon_module_slots_bonus uint16
---@field mining_drill_module_slots_bonus uint16
---@field module_multipliers table<ModuleEffectName, float>

---@return NamedPrototypes<FPQualityPrototype>
function generator.qualities.generate()
    local qualities = {}  ---@type NamedPrototypes<FPQualityPrototype>

    for _, proto in pairs(prototypes.quality) do
        if proto.hidden == false or proto.name == "normal" then
            local sprite = "quality/" .. proto.name
            if helpers.is_valid_sprite_path(sprite) then
                ---@diagnostic disable-next-line: missing-fields
                local quality = {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = sprite,
                    rich_text = {"", "[quality=" .. proto.name .. "] ",
                        generator.util.colored_rich_text(proto.localised_name, proto.color)},
                    always_show = proto.draw_sprite_by_default,
                    level = proto.level,
                    default_multiplier = proto.default_multiplier,
                    beacon_power_usage_multiplier = proto.beacon_power_usage_multiplier,
                    mining_drill_resource_drain_multiplier = proto.mining_drill_resource_drain_multiplier,
                    beacon_module_slots_bonus = proto.beacon_module_slots_bonus,
                    mining_drill_module_slots_bonus = proto.mining_drill_module_slots_bonus,
                    module_multipliers = {
                        consumption = proto.module_consumption_multiplier,
                        speed = proto.module_speed_multiplier,
                        productivity = proto.module_productivity_multiplier,
                        pollution = proto.module_pollution_multiplier,
                        quality = proto.module_quality_multiplier
                    }
                }  ---@type FPQualityPrototype
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

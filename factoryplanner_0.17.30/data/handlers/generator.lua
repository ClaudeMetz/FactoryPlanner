generator = {}

-- Inserts given prototype into given table t and adds it to t's map
-- Example: type = "recipes"
local function insert_proto(t, type_name, proto)
    table.insert(t[type_name], proto)
    local id = #t[type_name]
    t[type_name][id].id = id
    t.map[proto.name] = id
end

-- Inserts given proto into a two layers deep table t
-- (category and type are generic terms here, describing the first and second level of t)
-- Example: category_name = "categories", category = "steam", type_name = "machines"
local function deep_insert_proto(t, category_name, category, type_name, proto)
    if t.map[category] == nil then
        table.insert(t[category_name], {[type_name] = {}, map = {}, name = category})
        local id = #t[category_name]
        t[category_name][id].id = id
        t.map[category] = id
    end

    local category_entry = t[category_name][t.map[category]]
    insert_proto(category_entry, type_name, proto)
end


-- Returns the names of the recipes that shouldn't be included
local function undesirable_recipes()
    local undesirables = 
    {
        ["small-plane"] = false,
        ["electric-energy-interface"] = false,
        ["railgun"] = false,
        ["railgun-dart"] = false,
        ["player-port"] = false
    }

    -- Leaves loaders in if LoaderRedux is loaded
    if game.active_mods["LoaderRedux"] == nil then
        undesirables["loader"] = false
        undesirables["fast-loader"] = false
        undesirables["express-loader"] = false
    end
    
    return undesirables
end

-- Returns all standard recipes + custom mining, steam and rocket recipes
function generator.all_recipes()
    local all_recipes = {recipes = {}, map = {}}
    
    local function mining_recipe()
        return {
            hidden = false,
            group = {name="intermediate_products", order="c"},
            subgroup = {name="mining", order="z"}
        }
    end
    
    local undesirables = undesirable_recipes()
    -- Adding all standard recipes minus the undesirable ones
    for recipe_name, proto in pairs(game.recipe_prototypes) do
        -- Avoid any recipes that are undesirable or have no machine to produce them
        local category_id = new.all_machines.map[proto.category]
        if undesirables[recipe_name] == nil and category_id ~= nil then
            local recipe = {
                name = proto.name,
                localised_name = proto.localised_name,
                category = proto.category,
                energy = proto.energy,
                ingredients = proto.ingredients,
                products = proto.products,
                main_product = proto.main_product,
                hidden = proto.hidden,
                order = proto.order,
                group = proto.group,
                subgroup = proto.subgroup
            }
            insert_proto(all_recipes, "recipes", recipe)
        end
    end

    -- Adding all (solid) mining recipes
    -- (Inspired by https://github.com/npo6ka/FNEI/commit/58fef0cd4bd6d71a60b9431cb6fa4d96d2248c76)
    for _, proto in pairs(game.entity_prototypes) do
        -- Adds all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category and 
            proto.mineable_properties.products[1].type ~= "fluid" then
            local recipe = mining_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.localised_name = proto.localised_name
            recipe.order = proto.order
            recipe.category = proto.resource_category
            -- Set energy to mining time so the forumla for the machine_count works out
            recipe.energy = proto.mineable_properties.mining_time
            recipe.ingredients = {{type="entity", name=proto.name, amount=1}}
            recipe.products = proto.mineable_properties.products
            recipe.main_product = recipe.products[1]

            -- Add mining fluid, if required
            if proto.mineable_properties.required_fluid then
                table.insert(recipe.ingredients, {
                    type = "fluid",
                    name = proto.mineable_properties.required_fluid,
                    amount = proto.mineable_properties.fluid_amount
                })
                recipe.category = "complex-solid"
            end

            insert_proto(all_recipes, "recipes", recipe)
        end
    end
    
    -- Adds a recipe for producing (vanilla) steam
    local steam_recipe = mining_recipe()
    steam_recipe.name = "impostor-steam"
    steam_recipe.localised_name = {"fluid-name.steam"}   -- official locale
    steam_recipe.category = "steam"
    steam_recipe.order = "z"
    steam_recipe.energy = 1
    steam_recipe.ingredients = {{type="fluid", name="water", amount=60}}
    steam_recipe.products = {{type="fluid", name="steam", amount=60}}
    steam_recipe.main_product = steam_recipe.products[1]
    insert_proto(all_recipes, "recipes", steam_recipe)
    
    -- Adds a convenient space science recipe
    local rocket_recipe = {
        name = "fp-space-science-pack",
        localised_name = {"item-name.space-science-pack"},  -- official locale
        category = "rocket-building",
        hidden = false,
        energy = 0,
        group = {name="intermediate-products", order="c"},
        subgroup = {name="science-pack", order="g"},
        order = "x[fp-space-science-pack]",
        ingredients = {
            {type="item", name="rocket-part", amount=100},
            {type="item", name="satellite", amount=1}
        },
        products = {{type="item", name="space-science-pack", amount=1000}}
    }
    insert_proto(all_recipes, "recipes", rocket_recipe)
    
    return all_recipes
end


-- Returns the names of the recipes that shouldn't be included
local function undesirable_items()
    return {
        item = {
        },
        fluid = {
        },
        entity = {
        }
    }
end

-- Returns all relevant items and fluids
function generator.all_items()
    local all_items = {types = {}, map = {}}

    local function add_item(table, item)
        if table[item.type] == nil then
            table[item.type] = {}
        end
        table[item.type][item.name] = true
    end

    -- Create a table containing every item that is either a product or an ingredient to at least one recipe
    local relevant_items = {}
    for _, recipe in pairs(new.all_recipes.recipes) do
        for _, product in pairs(recipe.products) do
            add_item(relevant_items, product)
        end
        for _, ingredient in pairs(recipe.ingredients) do
            add_item(relevant_items, ingredient)
        end
    end
    -- Manually add the rocket-part item for the custom space recipe
    add_item(relevant_items, game["item_prototypes"]["rocket-part"])
    
    -- Adding all standard items minus the undesirable ones
    local undesirables = undesirable_items()
    for type, item_table in pairs(relevant_items) do
        for item_name, _ in pairs(item_table) do
            if not undesirables[type][item_name] then
                local proto = game[type .. "_prototypes"][item_name]
                local hidden = false  -- "entity" types are never hidden
                if type == "item" then hidden = proto.has_flag("hidden")
                elseif type == "fluid" then hidden = proto.hidden end
                if not hidden or item_name == "rocket-part" then  -- exclude hidden items
                    local item = {
                        name = proto.name,
                        type = type,
                        localised_name = proto.localised_name,
                        order = proto.order,
                        group = proto.group,
                        subgroup = proto.subgroup
                    }
                    deep_insert_proto(all_items, "types", type, "items", item)
                end
            end
        end
    end
    
    return all_items
end


-- Maps all items to the recipes that produce them ([item_type][item_name] = {[recipe_name] = true})
-- This optimizes the recipe filtering process for the recipe picker
function generator.item_recipe_map()
    local map = {}

    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        for _, product in ipairs(recipe.products) do
            if map[product.type] == nil then
                map[product.type] = {}
            end
            if map[product.type][product.name] == nil then
                map[product.type][product.name] = {}
            end
            map[product.type][product.name][recipe.name] = true
        end
    end
    
    return map
end


-- Returns the names of the item groups that shouldn't be included
local function undesirable_item_groups()
    return {
        item = {
            ["creative-mod_creative-tools"] = false
        },
        recipe = {
            ["creative-mod_creative-tools"] = false
        }
    }
end

-- Returns a table containing all item groups for both items and recipes for easier reference
function generator.item_groups()
    local groups = {item = {groups={}, map={}}, recipe = {groups={}, map={}}}
    local undesirables = undesirable_item_groups()

    local function create_group(proto)
        return {
            name = proto.name,
            localised_name = proto.localised_name,
            sprite = "item-group/" .. proto.name
        }
    end

    if not global.all_items.types then return end
    for _, type in pairs(global.all_items.types) do
        for _, item in pairs(type.items) do
            -- Don't continue if groups are invalid; this is the case when the configuration changed, and
            -- this function will be re-run once the global tables are updated
            if item.group.valid then
                if not groups.item.map[item.group.name] and undesirables.item[item.group.name] == nil then
                    insert_proto(groups.item, "groups", create_group(item.group))
                end
            end
        end
    end

    for _, recipe in pairs(global.all_recipes.recipes) do
        if recipe.group.valid then
            if not groups.recipe.map[recipe.group.name] and undesirables.recipe[recipe.group.name] == nil then
                insert_proto(groups.recipe, "groups", create_group(recipe.group))
            end
        end
    end

    return groups
end


-- Returns the names of the 'machines' that shouldn't be included
local function undesirable_machines()
    return {
        ["escape-pod-assembler"] = false
    }
end

-- Generates a table containing all machines for all categories
function generator.all_machines()
    local all_machines = {categories = {}, map = {}}
    
    local function generate_category_entry(category, proto)        
        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local ingredient_limit = proto.ingredient_count or 255
        local speed = proto.crafting_categories and proto.crafting_speed or proto.mining_speed
        local energy = proto.energy_usage or proto.max_energy_usage
        local burner = nil
        if proto.burner_prototype then
            burner = {
                categories = proto.burner_prototype.fuel_categories,
                effectivity = proto.burner_prototype.effectivity
            }
        end
        local machine = {
            name = proto.name,
            category = category,
            localised_name = proto.localised_name,
            ingredient_limit = ingredient_limit,
            speed = speed,
            energy = energy,
            allowed_effects = proto.allowed_effects,  -- might be nil
            module_limit = proto.module_inventory_size,
            burner = burner
        }
        return machine
    end

    local undesirables = undesirable_machines()
    for _, proto in pairs(game.entity_prototypes) do
        if proto.crafting_categories and proto.energy_usage ~= nil and undesirables[proto.name] == nil then
            for category, enabled in pairs(proto.crafting_categories) do
                if enabled then 
                    local machine = generate_category_entry(category, proto)
                    deep_insert_proto(all_machines, "categories", category, "machines", machine)
                end
            end

        -- Adds mining machines
        elseif proto.resource_categories then
            for category, enabled in pairs(proto.resource_categories) do
                -- Only supports solid mining recipes for now (no oil etc.)
                if enabled and category ~= "basic-fluid" then
                    local machine = generate_category_entry(category, proto)
                    deep_insert_proto(all_machines, "categories", category, "machines", machine)

                    -- Add separate category for mining with fluids that avoids the burner-miner
                    if category == "basic-solid" then
                        if not proto.burner_prototype then
                            local machine = generate_category_entry("complex-solid", proto)
                            deep_insert_proto(all_machines, "categories", "complex-solid", "machines", machine)
                        end
                    end
                end
            end
        end

        -- Adds machines that produce steam
        for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" and fluidbox.filter
              and fluidbox.filter.name == "steam" then
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
                        local machine = generate_category_entry("steam", proto)
                        
                        temp_diff = proto.target_temperature - input_fluidbox.filter.default_temperature
                        energy_per_unit = input_fluidbox.filter.heat_capacity * temp_diff
                        machine.speed = machine.energy / energy_per_unit

                        deep_insert_proto(all_machines, "categories", "steam", "machines", machine)
                    end
                end
            end
        end
    end
    
    return all_machines
end


-- Generates a table containing all available transport belts
function generator.all_belts()
    local all_belts = {belts = {}, map = {}}
    for _, proto in pairs(game.entity_prototypes) do
        if proto.type == "transport-belt" then
            insert_proto(all_belts, "belts", {
                name = proto.name,
                sprite = "entity/" .. proto.name,
                localised_name = proto.localised_name,
                throughput = proto.belt_speed * 480
            })
        end
    end
    return all_belts
end


-- Generates a table containing all fuels that can be used in a burner
-- (only supports chemical fuels for now)
function generator.all_fuels()
    local all_fuels = {fuels = {}, map = {}}
    for _, proto in pairs(game.item_prototypes) do
        if proto.fuel_value and proto.fuel_category == "chemical" then
            insert_proto(all_fuels, "fuels", {
                name = proto.name,
                type = proto.type,
                sprite = proto.type .. "/" .. proto.name,
                localised_name = proto.localised_name,
                fuel_category = proto.fuel_category,
                fuel_value = proto.fuel_value
            })
        end
    end
    return all_fuels
end


-- Generates a table containing all available modules
function generator.all_modules()
    local all_modules = {categories = {}, map = {}}
    for _, proto in pairs(game.item_prototypes) do
        if proto.type == "module" then
            -- Convert limitations-table to a [recipe_name] -> true fromat
            local limitations = {}
            for _, recipe_name in pairs(proto.limitations) do
                limitations[recipe_name] = true
            end

            local module = {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "item/" .. proto.name,
                category = proto.category,
                tier = proto.tier,
                effects = proto.module_effects,
                limitations = limitations
            }
            deep_insert_proto(all_modules, "categories", proto.category, "modules", module)
        end
    end
    return all_modules
end

-- Generates a table containing all module per category, ordered by tier
function generator.module_tier_map()
    local map = {}

    if not global.all_modules then return end
    for _, category in pairs(global.all_modules.categories) do
        map[category.id] = {}
        for _, module in pairs(category.modules) do
            map[category.id][module.tier] = module
        end
    end
    
    return map
end


-- Generates a table containing all available beacons
function generator.all_beacons()
    local all_beacons = {beacons = {}, map = {}}
    for _, proto in pairs(game.entity_prototypes) do
        if proto.distribution_effectivity ~= nil then
            insert_proto(all_beacons, "beacons", {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "entity/" .. proto.name,
                allowed_effects = proto.allowed_effects,
                module_limit = proto.module_inventory_size,
                effectivity = proto.distribution_effectivity
            })
        end
    end
    return all_beacons
end
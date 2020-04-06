generator = {}

-- Inserts given prototype into given table t and adds it to t's map
-- Example: type_name = "recipes"
local function insert_proto(t, type_name, proto, add_identifier)
    table.insert(t[type_name], proto)
    local id = #t[type_name]
    proto.id = id
    t.map[proto.name] = id
    if add_identifier then proto.identifier = id end
end

-- Inserts given proto into a two layers deep table t
-- (category and type are generic terms here, describing the first and second level of t)
-- Example: category_name = "categories", category = "steam", type_name = "machines"
local function deep_insert_proto(t, category_name, category, type_name, proto, add_identifier)
    if t.map[category] == nil then
        table.insert(t[category_name], {[type_name] = {}, map = {}, name = category})
        local id = #t[category_name]
        t[category_name][id].id = id
        t.map[category] = id
    end

    local category_entry = t[category_name][t.map[category]]
    insert_proto(category_entry, type_name, proto)
    if add_identifier then proto.identifier = t.map[category] .. "_" .. proto.id end
end


-- Generates a table imitating the a LuaGroup to avoid lua-cpp bridging
local function generate_group_table(group)
    return {name=group.name, localised_name=group.localised_name, order=group.order, valid=true}
end

-- Returns nil if no effect is true, returns the effects otherwise
local function format_allowed_effects(allowed_effects)
    if allowed_effects == nil then return nil end
    for _, allowed in pairs(allowed_effects) do
        if allowed == true then return allowed_effects end
    end
    return nil  -- all effects are false
end


-- Determines whether this recipe is a recycling one or not
-- Compatible with: 'Industrial Revolution', 'Reverse Factory', 'Recycling Machines'
local function is_recycling_recipe(proto)
    local active_mods = {
        DIR = game.active_mods["IndustrialRevolution"],
        RF = game.active_mods["reverse-factory"],
        ZR = game.active_mods["ZRecycling"]
    }

    if active_mods.DIR and string.match(proto.name, "^scrap%-.*") then
        return true
    elseif active_mods.RF and string.match(proto.name, "^rf%-.*") then
        return true
    elseif active_mods.ZR and string.match(proto.name, "^dry411srev%-.*") then
        return true
    else
        return false
    end
end

-- Determines whether the given recipe is a barreling or stacking one
-- Compatible with: 'Deadlock's Stacking Beltboxes & Compact Loaders' and extensions of it
local function is_barreling_recipe(proto)
    if proto.subgroup.name == "empty-barrel" or proto.subgroup.name == "fill-barrel" then
        return true
    elseif string.match(proto.name, "^deadlock%-stacks%-.*") or string.match(proto.name, "^deadlock%-packrecipe%-.*")
      or string.match(proto.name, "^deadlock%-unpackrecipe%-.*") then
        return true
    else
        return false
    end
end


-- Returns the appropriate prototype name for the given item, incorporating temperature
local function format_temperature_name(item, name)
    return (item.temperature) and string.gsub(name, "-[0-9]+$", "") or name
end

-- Returns the appropriate localised string for the given item, incorporating temperature
local function format_temperature_localised_name(item, proto)
    return (item.temperature ~= nil) and {"", proto.localised_name, " (",
      item.temperature, {"fp.unit_celsius"}, ")"} or proto.localised_name
end


-- Determines the actual amount of items that a recipe product or ingredient equates to
local function generate_formatted_item(base_item, type)
    local actual_amount, proddable_amount = 0, 0
    if base_item.amount_max ~= nil and base_item.amount_min ~= nil then
        actual_amount = ((base_item.amount_max + base_item.amount_min) / 2) * base_item.probability
        
        -- I'm unsure whether this calculation is correct for this type of recipe spec
        -- A definition with max/min and catalysts might not even be possible/in use
        if type == "ingredient" then
            proddable_amount = actual_amount - (base_item.catalyst_amount or 0)
        else  -- type == "product"
            proddable_amount = (base_item.catalyst_amount or 0)
        end

    elseif base_item.probability ~= nil then
        actual_amount = base_item.amount * base_item.probability
        if type == "ingredient" then
            proddable_amount = (base_item.amount - (base_item.catalyst_amount or 0)) * base_item.probability
        else  -- type == "product"
            proddable_amount = (base_item.catalyst_amount or 0) * base_item.probability
        end
    else
        actual_amount = base_item.amount
        if type == "ingredient" then
            proddable_amount = base_item.amount - (base_item.catalyst_amount or 0)
        else  -- type == "product"
            proddable_amount = (base_item.catalyst_amount or 0)
        end
    end

    -- This will probably screw up the main_product detection down the line
    if base_item.temperature ~= nil then
        base_item.name = base_item.name .. "-" .. base_item.temperature
    end

    return {
        name = base_item.name,
        type = base_item.type,
        amount = actual_amount,
        proddable_amount = proddable_amount,
        temperature = base_item.temperature
    }
end

-- Determines the net amount that the given recipe consumes of the given item (might be negative)
local function determine_net_ingredient_amount(recipe_proto, item)
    local net_amount = 0
    for _, ingredient in pairs(recipe_proto.ingredients) do
        -- Find the given item in the ingredient list
        if ingredient.type == item.type and ingredient.name == item.name then
            net_amount = ingredient.amount  -- actual amount
            break
        end
    end

    for _, product in pairs(recipe_proto.products) do
        -- Find the given item in the product list
        if product.type == item.type and product.name == item.name then
            net_amount = net_amount - product.amount
            break
        end
    end
    
    return net_amount
end

-- Determines the net amount that the given recipe produces of the given item (might be negative)
local function determine_net_product_amount(recipe_proto, item)
    local net_amount = 0
    for _, product in pairs(recipe_proto.products) do
        -- Mining recipes' net amounts always equal their main_product's amount
        if recipe_proto.mining and product.name == recipe_proto.main_product.name then
            return product.amount
        end

        -- Find the given item in the product list
        if product.type == item.type and product.name == item.name then
            net_amount = product.amount  -- actual amount
            break
        end
    end

    for _, ingredient in pairs(recipe_proto.ingredients) do
        -- Find the given item in the ingredient list
        if ingredient.type == item.type and ingredient.name == item.name then
            net_amount = net_amount - ingredient.amount
            break
        end
    end
    
    return net_amount
end

-- Formats the products/ingredients of a recipe for more convenient use
local function format_recipe_products_and_ingredients(recipe_proto)
    local ingredients = {}
    for _, base_ingredient in ipairs(recipe_proto.ingredients) do
        local formatted_ingredient = generate_formatted_item(base_ingredient, "ingredient")
        table.insert(ingredients, formatted_ingredient)
    end
    recipe_proto.ingredients = ingredients

    local products = {}
    for _, base_product in ipairs(recipe_proto.products) do
        local formatted_product = generate_formatted_item(base_product, "product")
        table.insert(products, formatted_product)

        -- Update the main product as well, if present
        if recipe_proto.main_product ~= nil and
          formatted_product.type == recipe_proto.main_product.type and
          formatted_product.name == recipe_proto.main_product.name then
            recipe_proto.main_product = formatted_product
        end
    end
    recipe_proto.products = products
    
    -- Determine the net amount after the actual amounts have been calculated
    for _, formatted_ingredient in ipairs(recipe_proto.ingredients) do
        formatted_ingredient.net_amount = determine_net_ingredient_amount(recipe_proto, formatted_ingredient)
    end

    -- Determine the net amount after the actual amounts have been calculated
    for _, formatted_product in ipairs(recipe_proto.products) do
        formatted_product.net_amount = determine_net_product_amount(recipe_proto, formatted_product)
    end
end


-- Adds the tooltip for the given recipe
function add_recipe_tooltip(recipe)
    local tooltip = {"", recipe.localised_name}
    local current_table = tooltip
    local current_depth = 1

    -- Inserts strings in a way to minimize depth ('nestedness') of the localised string
    local function multi_insert(t)
        for _, e in pairs(t) do
            -- Nest localised string deeper if the limit of 20 elements per 'level' is reached
            if table_size(current_table) == 20 then
                -- If the depth is more than 8, the serpent deserializer will crash when loading the save
                -- because the resulting global table will be 'too complex'
                if current_depth == 8 then return tooltip end

                table.insert(current_table, {""})
                current_table = current_table[table_size(current_table)]
                current_depth = current_depth + 1
            end
            table.insert(current_table, e)
        end
    end

    if recipe.energy ~= nil then multi_insert{"\n  ", {"fp.crafting_time"}, (":  " .. recipe.energy)} end
    for _, item_type in ipairs({"ingredients", "products"}) do
        multi_insert{"\n  ", {"fp." .. item_type}, ":"}
        if #recipe[item_type] == 0 then
            multi_insert{"\n    ", {"fp.none"}}
        else
            for _, item in ipairs(recipe[item_type]) do
                local name = format_temperature_name(item, item.name)
                local proto = game[item.type .. "_prototypes"][name]
                local localised_name = format_temperature_localised_name(item, proto)
                multi_insert{("\n    " .. "[" .. item.type .. "=" .. name .. "] " .. item.amount .. "x "), localised_name}
            end
        end
    end
    if devmode then multi_insert{("\n" .. recipe.name)} end

    recipe.tooltip = tooltip
end

-- Adds the tooltip for the given item
local function add_item_tooltip(item)
    local tooltip = item.localised_name
    if devmode then tooltip = {"", item.localised_name, ("\n" .. item.name)} end
    item.tooltip = tooltip
end


-- Sorts the objects according to their group, subgroup and order
local function create_object_tree(objects)
    local function sorting_function(a, b)
        if a.group.order < b.group.order then
            return true
        elseif a.group.order > b.group.order then
            return false
        elseif a.subgroup.order < b.subgroup.order then
            return true
        elseif a.subgroup.order > b.subgroup.order then
            return false
        elseif a.order < b.order then
            return true
        elseif a.order > b.order then
            return false
        end
    end
    
    table.sort(objects, sorting_function)
    return objects
end


-- Determines every recipe that is researchable or enabled by default
local function determine_researchable_recipes()
    local map = {}

    for _, proto in pairs(game.technology_prototypes) do
        if not proto.hidden then
            for _, effect in pairs(proto.effects) do
                if effect.type == "unlock-recipe" then
                    map[effect.recipe] = true
                end
            end
        end
    end
    
    return map
end


-- Returns all standard recipes + custom mining, steam and rocket recipes
function generator.all_recipes()
    local all_recipes = {recipes = {}, map = {}}
    
    local function mining_recipe()
        return {
            hidden = false,
            group = {name="intermediate-products", localised_name={"item-group-name.intermediate-products"},
              order="c", valid=true},
            use_limitations = false,
            custom = true
        }
    end
    
    local researchable_recipes = determine_researchable_recipes()
    -- Adding all standard recipes
    for recipe_name, proto in pairs(game.recipe_prototypes) do
        -- Avoid any recipes that have no machine to produce them or are unresearchable
        local category_id = new.all_machines.map[proto.category]
        if category_id ~= nil and (proto.enabled or researchable_recipes[recipe_name]) then
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
                recycling = is_recycling_recipe(proto),
                barreling = is_barreling_recipe(proto),
                use_limitations = true,
                custom = false,
                hidden = proto.hidden,
                order = proto.order,
                group = generate_group_table(proto.group),
                subgroup = generate_group_table(proto.subgroup)
            }
            
            format_recipe_products_and_ingredients(recipe)
            --add_recipe_tooltip(recipe)
            insert_proto(all_recipes, "recipes", recipe, true)
        end
    end

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
                local recipe = mining_recipe()
                recipe.name = "impostor-" .. proto.name
                recipe.localised_name = proto.localised_name
                recipe.sprite = products[1].type .. "/" .. products[1].name
                recipe.order = proto.order
                recipe.subgroup = {name="mining", order="y", valid=true}
                recipe.category = proto.resource_category
                recipe.mining = true
                -- Set energy to mining time so the forumla for the machine_count works out
                recipe.energy = proto.mineable_properties.mining_time
                recipe.emissions_multiplier = 1
                recipe.ingredients = {{type="entity", name=proto.name, amount=1}}
                recipe.products = products
                recipe.main_product = recipe.products[1]

                -- Add mining fluid, if required
                if proto.mineable_properties.required_fluid then
                    table.insert(recipe.ingredients, {
                        type = "fluid",
                        name = proto.mineable_properties.required_fluid,
                        amount = proto.mineable_properties.fluid_amount
                    })
                    if recipe.category == "basic-solid" then recipe.category = "complex-solid" end
                end

                format_recipe_products_and_ingredients(recipe)
                add_recipe_tooltip(recipe)
                insert_proto(all_recipes, "recipes", recipe, true)

            --else
                -- crude-oil and angels-natural-gas go here (not interested atm)
            end

        -- Add offshore-pump fluid recipes
        elseif proto.fluid then
            local recipe = mining_recipe()
            recipe.name = "impostor-" .. proto.fluid.name .. "-" .. proto.name
            recipe.localised_name = proto.fluid.localised_name
            recipe.sprite = "fluid/" .. proto.fluid.name
            recipe.order = proto.order
            recipe.subgroup = {name="fluids", order="z", valid=true}
            recipe.category = proto.name  -- use proto name so every pump has it's own category
            recipe.energy = 1
            recipe.emissions_multiplier = 1
            recipe.ingredients = {}
            recipe.products = {{type="fluid", name=proto.fluid.name, amount=(proto.pumping_speed * 60)}}
            recipe.main_product = recipe.products[1]

            format_recipe_products_and_ingredients(recipe)
            add_recipe_tooltip(recipe)
            insert_proto(all_recipes, "recipes", recipe, true)
        end
    
        -- Adds a recipe for producing steam from a boiler
        for _, fluidbox in ipairs(proto.fluidbox_prototypes) do
            if fluidbox.production_type == "output" and fluidbox.filter
                and fluidbox.filter.name == "steam" then
                -- Exclude any boilers that use heat as their energy source
                if proto.burner_prototype or proto.electric_energy_source_prototype then
                    local temperature = proto.target_temperature
                    local recipe = mining_recipe()
                    recipe.name = "impostor-steam-" .. temperature
                    recipe.localised_name = {"", {"fluid-name.steam"}, " at ", temperature, {"fp.unit_celsius"}}
                    recipe.sprite = "fluid/steam"
                    recipe.category = "steam-" .. temperature
                    recipe.order = "z-" .. temperature
                    recipe.subgroup = {name="fluids", order="z", valid=true}
                    recipe.energy = 1
                    recipe.emissions_multiplier = 1
                    recipe.ingredients = {{type="fluid", name="water", amount=60}}
                    recipe.products = {{type="fluid", name="steam", amount=60, temperature=temperature}}
                    recipe.main_product = recipe.products[1]

                    format_recipe_products_and_ingredients(recipe)
                    add_recipe_tooltip(recipe)
                    -- Prevent duplicate recipes, in case more than one boiler produces the same temperature of steam
                    if all_recipes.map[recipe.name] == nil then insert_proto(all_recipes, "recipes", recipe, true) end
                end
            end
        end
    end

    -- Add a general steam recipe that works with every boiler
    if game["fluid_prototypes"]["steam"] then  -- make sure the steam prototype exists
        local steam_recipe = mining_recipe()
        steam_recipe.name = "fp-general-steam"
        steam_recipe.localised_name = {"fluid-name.steam"}
        steam_recipe.sprite = "fluid/steam"
        steam_recipe.category = "general-steam"
        steam_recipe.order = "z-0"
        steam_recipe.subgroup = {name="fluids", order="z", valid=true}
        steam_recipe.energy = 1
        steam_recipe.emissions_multiplier = 1
        steam_recipe.ingredients = {{type="fluid", name="water", amount=60}}
        steam_recipe.products = {{type="fluid", name="steam", amount=60}}
        steam_recipe.main_product = steam_recipe.products[1]

        format_recipe_products_and_ingredients(steam_recipe)
        add_recipe_tooltip(steam_recipe)
        insert_proto(all_recipes, "recipes", steam_recipe, true)
    end
    
    -- Adds a convenient space science recipe
    local rocket_recipe = {
        name = "fp-space-science-pack",
        localised_name = {"item-name.space-science-pack"},  -- official locale
        sprite = "item/space-science-pack",
        category = "rocket-building",
        hidden = false,
        energy = 0,
        emissions_multiplier = 1,
        group = {name="intermediate-products", localised_name={"item-group-name.intermediate-products"},
          order="c", valid=true},
        subgroup = {name="science-pack", order="g", valid=true},
        order = "x[fp-space-science-pack]",
        ingredients = {
            {type="item", name="rocket-part", amount=100},
            {type="item", name="satellite", amount=1}
        },
        products = {{type="item", name="space-science-pack", amount=1000}},
        custom = true
    }

    format_recipe_products_and_ingredients(rocket_recipe)
    add_recipe_tooltip(rocket_recipe)
    insert_proto(all_recipes, "recipes", rocket_recipe, true)
    
    return all_recipes
end

--[[ -- Generates a list of all recipes, sorted for display in the picker
function generator.sorted_recipes()
    local recipes = {}
    for _, recipe in ipairs(global.all_recipes.recipes) do
        -- Silly checks needed here for migration purposes
        if recipe.group.valid and recipe.subgroup.valid then table.insert(recipes, recipe) end
    end
    return create_object_tree(recipes)
end ]]

-- Returns a list of recipe groups in their proper order
function generator.ordered_recipe_groups()
    group_dict = {}

    -- Make a dict with all recipe groups
    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        if group_dict[recipe.group.name] == nil then
            group_dict[recipe.group.name] = recipe.group
        end
    end

    -- Invert it
    local groups = {}
    for _, group in pairs(group_dict) do
        table.insert(groups, group)
    end

    -- Sort it
    local function sorting_function(a, b)
        if a.order < b.order then
            return true
        elseif a.order > b.order then
            return false
        end
    end
    table.sort(groups, sorting_function)

    return groups
end


-- Returns all relevant items and fluids
function generator.all_items()
    local all_items = {types = {}, map = {}}

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
            local proto_name = format_temperature_name(item_details, item_name)
            local proto = game[type .. "_prototypes"][proto_name]
            local localised_name = format_temperature_localised_name(item_details, proto)
            local order = (item_details.temperature) and (proto.order .. item_details.temperature) or proto.order

            local hidden = false  -- "entity" types are never hidden
            if type == "item" then hidden = proto.has_flag("hidden")
            elseif type == "fluid" then hidden = proto.hidden end
            
            if not hidden or item_name == "rocket-part" then  -- exclude hidden items
                local item = {
                    name = item_name,
                    type = type,
                    sprite = type .. "/" .. proto.name,
                    localised_name = localised_name,
                    ingredient_only = not item_details.is_product,
                    temperature = item_details.temperature,
                    order = order,
                    group = generate_group_table(proto.group),
                    subgroup = generate_group_table(proto.subgroup)
                }

                add_item_tooltip(item)
                deep_insert_proto(all_items, "types", type, "items", item, true)
            end
        end
    end
    
    return all_items
end

-- Generates a list of all items, sorted for display in the picker
function generator.sorted_items()
    -- Combines item and fluid prototypes into an unsorted number-indexed array
    local items = {}
    local all_items = global.all_items
    for _, type in pairs({"item", "fluid"}) do
        for _, item in pairs(all_items.types[all_items.map[type]].items) do
            -- Silly checks needed here for migration purposes
            if item.group.valid and item.subgroup.valid then table.insert(items, item) end
        end
    end
    return create_object_tree(items)
end


-- Maps all items to the recipes that produce them ([item_type][item_name] = {[recipe_id] = true}
function generator.product_recipe_map()
    local map = {}

    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        for _, product in ipairs(recipe.products) do
            -- Ignores recipes that produce a net item/fluid amount <= 0
            if product.net_amount and product.net_amount > 0 then
                map[product.type] = map[product.type] or {}
                map[product.type][product.name] = map[product.type][product.name] or {}
                map[product.type][product.name][recipe.id] = true
            end
        end
    end
    
    return map
end

-- Maps all items to the recipes that consume them ([item_type][item_name] = {[recipe_id] = true}
function generator.ingredient_recipe_map()
    local map = {}

    if not global.all_recipes.recipes then return end
    for _, recipe in pairs(global.all_recipes.recipes) do
        for _, ingredient in ipairs(recipe.ingredients) do
            -- Ignores recipes that consume a net item/fluid amount <= 0
            if ingredient.net_amount and ingredient.net_amount > 0 then
                map[ingredient.type] = map[ingredient.type] or {}
                map[ingredient.type][ingredient.name] = map[ingredient.type][ingredient.name] or {}
                map[ingredient.type][ingredient.name][recipe.id] = true
            end
        end
    end

    return map
end

-- Generates a table mapping item identifier to their prototypes
function generator.identifier_item_map()
    local map = {}
    local all_items = global.all_items
    for _, type in pairs({"item", "fluid"}) do
        for _, item in pairs(all_items.types[all_items.map[type]].items) do
            -- Identifier existance-check for migration reasons
            if item.identifier ~= nil then map[item.identifier] = item end
        end
    end
    return map
end


-- Generates a table containing all machines for all categories
function generator.all_machines()
    local all_machines = {categories = {}, map = {}}
    
    local function generate_category_entry(category, proto)        
        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local speed = proto.crafting_categories and proto.crafting_speed or proto.mining_speed
        local energy_usage = proto.energy_usage or proto.max_energy_usage or 0

        local burner, emissions = nil, 0  -- emissions remain at 0 if no energy source is present
        if proto.burner_prototype then
            burner = {
                categories = proto.burner_prototype.fuel_categories,
                effectivity = proto.burner_prototype.effectivity
            }
            emissions = proto.burner_prototype.emissions
        elseif proto.electric_energy_source_prototype then
            emissions = proto.electric_energy_source_prototype.emissions
        end

        local machine = {
            name = proto.name,
            category = category,
            localised_name = proto.localised_name,
            sprite = "entity/" .. proto.name,
            ingredient_limit = (proto.ingredient_count or 255),
            speed = speed,
            energy_usage = energy_usage,
            emissions = emissions,
            base_productivity = (proto.base_productivity or 0),
            allowed_effects = format_allowed_effects(proto.allowed_effects),
            module_limit = (proto.module_inventory_size or 0),
            burner = burner
        }

        return machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if not proto.has_flag("hidden") and proto.crafting_categories and proto.energy_usage ~= nil then
            for category, enabled in pairs(proto.crafting_categories) do
                if enabled then 
                    local machine = generate_category_entry(category, proto)
                    deep_insert_proto(all_machines, "categories", category, "machines", machine)
                end
            end

        -- Add mining machines
        elseif proto.resource_categories then
            for category, enabled in pairs(proto.resource_categories) do
                -- Only supports solid mining recipes for now (no oil etc.)
                if enabled and category ~= "basic-fluid" then
                    local machine = generate_category_entry(category, proto)
                    machine.mining = true
                    deep_insert_proto(all_machines, "categories", category, "machines", machine)

                    -- Add separate category for mining with fluids that avoids the burner-miner
                    if category == "basic-solid" then
                        if not proto.burner_prototype then
                            local machine = generate_category_entry("complex-solid", proto)
                            machine.mining = true
                            deep_insert_proto(all_machines, "categories", "complex-solid", "machines", machine)
                        end
                    end
                end
            end
        
        -- Add offshore pumps
        elseif proto.fluid then
            local machine = generate_category_entry(proto.name, proto)
            machine.speed = 1  -- pumping speed included in the recipe product-amount
            deep_insert_proto(all_machines, "categories", proto.name, "machines", machine)
        end

        -- Add machines that produce steam (ie. boilers)
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
                        local category = "steam-" .. proto.target_temperature
                        local machine = generate_category_entry(category, proto)
                        
                        local temp_diff = proto.target_temperature - input_fluidbox.filter.default_temperature
                        local energy_per_unit = input_fluidbox.filter.heat_capacity * temp_diff
                        machine.speed = machine.energy_usage / energy_per_unit

                        deep_insert_proto(all_machines, "categories", category, "machines", machine)

                        -- Add every boiler to the general steam category (steam without temperature)
                        local general_machine = util.table.deepcopy(machine)
                        general_machine.category = "general-steam"
                        deep_insert_proto(all_machines, "categories", "general-steam", "machines", general_machine)
                    end
                end
            end
        end
    end
    
    return all_machines
end


-- Determines a suitable crafting machine sprite path, according to what is available
function generator.find_crafting_machine_sprite()
    -- Try these categories first, one of them should exist
    local categories = {"crafting", "advanced-crafting", "basic-crafting"}
    for _, category_name in ipairs(categories) do
        local category_id = global.all_machines.map[category_name]
        if category_id ~= nil then
            local machines = global.all_machines.categories[category_id].machines
            return machines[table_size(machines)].sprite
        end
    end

    -- If none of the specified categories exist, just pick the top tier machine of the first one
    local machines = global.all_machines.categories[1].machines
    return machines[table_size(machines)].sprite
end


-- Generates a table containing all available transport belts
function generator.all_belts()
    local all_belts = {belts = {}, map = {}}

    for _, proto in pairs(game.entity_prototypes) do
        if proto.type == "transport-belt" then
            insert_proto(all_belts, "belts", {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "entity/" .. proto.name,
                rich_text = "[entity=" .. proto.name .. "]",
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
    local items = new.all_items.types[new.all_items.map["item"]]

    for _, proto in pairs(game.item_prototypes) do
        -- Only use fuels that were actually detected/accepted to be items,
        -- and have non-zero and non-infinite fuel values
        if proto.fuel_value and proto.fuel_category == "chemical" and items.map[proto.name]
          and proto.fuel_value ~= 0 and proto.fuel_value < 1e+21 then
            insert_proto(all_fuels, "fuels", {
                name = proto.name,
                type = proto.type,
                sprite = proto.type .. "/" .. proto.name,
                localised_name = proto.localised_name,
                fuel_category = proto.fuel_category,
                fuel_value = proto.fuel_value,
                emissions_multiplier = proto.fuel_emissions_multiplier
            })
        end
    end
    
    return all_fuels
end


-- Generates a table containing all available modules
function generator.all_modules()
    local all_modules = {categories = {}, map = {}}

    for _, proto in pairs(game.item_prototypes) do
        if proto.type == "module" and not proto.has_flag("hidden") then
            local limitations = {}  -- Convert limitations-table to a [recipe_name] -> true format
            for _, recipe_name in pairs(proto.limitations) do limitations[recipe_name] = true end
            
            local sprite = "item/" .. proto.name
            if game.is_valid_sprite_path(sprite) then
                deep_insert_proto(all_modules, "categories", proto.category, "modules", {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = sprite,
                    category = proto.category,
                    tier = proto.tier,
                    effects = proto.module_effects or {},
                    limitations = limitations
                })
            end
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
        if proto.distribution_effectivity ~= nil and not proto.has_flag("hidden") then
            local sprite = "entity/" .. proto.name
            if game.is_valid_sprite_path(sprite) then
                insert_proto(all_beacons, "beacons", {
                    name = proto.name,
                    localised_name = proto.localised_name,
                    sprite = sprite,
                    category = "fp_beacon",  -- custom category to be similar to machines
                    allowed_effects = format_allowed_effects(proto.allowed_effects),
                    module_limit = proto.module_inventory_size,
                    effectivity = proto.distribution_effectivity,
                    energy_usage = proto.energy_usage or proto.max_energy_usage or 0
                })
            end
        end
    end

    return all_beacons
end
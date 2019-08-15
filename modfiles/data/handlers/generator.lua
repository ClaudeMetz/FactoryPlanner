generator = {}

-- Inserts given prototype into given table t and adds it to t's map
-- Example: type = "recipes"
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


-- Determines whether this recipe is a recycling one
-- Compatible with: Reverse Factory, Deadlock's Industrial Revolution
local active_mods = nil
local function is_recycling_recipe(proto)
    active_mods = active_mods or {
        DIR = game.active_mods["DeadlockIndustry"],
        RF = game.active_mods["reverse-factory"]
    }

    if active_mods.DIR and string.match(proto.name, "^disassemble%-.*") then
        return true
    elseif active_mods.RF and string.match(proto.name, "^rf%-.*") then
        return true
    else
        return false
    end
end

-- Determines whether the given recipe is a barreling one
local function is_barreling_recipe(proto)
    return (proto.subgroup.name == "empty-barrel" or proto.subgroup.name == "fill-barrel")
end


-- Adds the tooltip for the given recipe
function add_recipe_tooltip(recipe)
    local tooltip = {}
    local current_table = tooltip
    -- Inserts strings in a way to minimize amount and depth of the localised string
    local function multi_insert(t)
        for _, e in pairs(t) do
            if table_size(current_table) == 18 then
                table.insert(current_table, {""})
                current_table = current_table[table_size(current_table)]
            end
            table.insert(current_table, e)
        end
    end

    if recipe.energy ~= nil then multi_insert{"\n  ", {"tooltip.crafting_time"}, (":  " .. recipe.energy)} end
    for _, item_type in ipairs({"ingredients", "products"}) do
        multi_insert{"\n  ", {"tooltip." .. item_type}, ":"}
        if #recipe[item_type] == 0 then
            multi_insert{"\n    ", {"tooltip.none"}}
        else
            for _, item in ipairs(recipe[item_type]) do
                produced_amount = data_util.determine_product_amount(item)
            
                multi_insert{("\n    " .. "[" .. item.type .. "=" .. item.name .. "] " .. produced_amount .. "x "),
                  game[item.type .. "_prototypes"][item.name].localised_name}
            end
        end
    end
    if devmode then multi_insert{("\n" .. recipe.name)} end

    recipe.tooltip = {"", recipe.localised_name, unpack(tooltip)}
end

-- Adds the tooltip for the given item
local function add_item_tooltip(item)
    local tooltip = item.localised_name
    if devmode then tooltip = {"", tooltip, ("\n" .. item.name)} end
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
            group = {name="intermediate-products", localised_name={"item-group-name.intermediate-products"},
              order="c", valid=true},
            use_limitations = false,
            custom = true
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
                category = proto.category,
                localised_name = proto.localised_name,
                sprite = "recipe/" .. proto.name,
                energy = proto.energy,
                ingredients = proto.ingredients,
                products = proto.products,
                main_product = proto.main_product,
                recycling = is_recycling_recipe(proto),
                barreling = is_barreling_recipe(proto),
                custom = false,
                hidden = proto.hidden,
                order = proto.order,
                group = generate_group_table(proto.group),
                subgroup = generate_group_table(proto.subgroup)
            }
            
            add_recipe_tooltip(recipe)
            insert_proto(all_recipes, "recipes", recipe, true)
        end
    end

    -- Adding all (solid) mining recipes
    -- (Inspired by https://github.com/npo6ka/FNEI/commit/58fef0cd4bd6d71a60b9431cb6fa4d96d2248c76)
    for _, proto in pairs(game.entity_prototypes) do
        -- Adds all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category then
            if proto.resource_category == "basic-solid" then
                local products = proto.mineable_properties.products
                local recipe = mining_recipe()
                recipe.name = "impostor-" .. proto.name
                recipe.localised_name = proto.localised_name
                recipe.sprite = products[1].type .. "/" .. products[1].name
                recipe.order = proto.order
                recipe.subgroup = {name="mining", order="y", valid=true}
                recipe.category = proto.resource_category
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
                        amount = proto.mineable_properties.fluid_amount
                    })
                    recipe.category = "complex-solid"
                end

                add_recipe_tooltip(recipe)
                insert_proto(all_recipes, "recipes", recipe, true)

            --elseif proto.resource_category == "basic-fluid" then
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
            recipe.ingredients = {}
            recipe.products = {{type="fluid", name=proto.fluid.name, amount=(proto.pumping_speed * 60)}}
            recipe.main_product = recipe.products[1]

            add_recipe_tooltip(recipe)
            insert_proto(all_recipes, "recipes", recipe, true)
        end
    end
    
    -- Adds a recipe for producing (vanilla) steam
    local steam_recipe = mining_recipe()
    steam_recipe.name = "impostor-steam"
    steam_recipe.localised_name = {"fluid-name.steam"}   -- official locale
    steam_recipe.sprite = "fluid/steam"
    steam_recipe.category = "steam"
    steam_recipe.order = "z"
    steam_recipe.subgroup = {name="fluids", order="z", valid=true}
    steam_recipe.energy = 1
    steam_recipe.ingredients = {{type="fluid", name="water", amount=60}}
    steam_recipe.products = {{type="fluid", name="steam", amount=60}}
    steam_recipe.main_product = steam_recipe.products[1]

    add_recipe_tooltip(steam_recipe)
    insert_proto(all_recipes, "recipes", steam_recipe, true)
    
    -- Adds a convenient space science recipe
    local rocket_recipe = {
        name = "fp-space-science-pack",
        localised_name = {"item-name.space-science-pack"},  -- official locale
        sprite = "item/space-science-pack",
        category = "rocket-building",
        hidden = false,
        energy = 0,
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

    add_recipe_tooltip(rocket_recipe)
    insert_proto(all_recipes, "recipes", rocket_recipe, true)
    
    return all_recipes
end

-- Generates a list of all recipes, sorted for display in the picker
function generator.sorted_recipes()
    local recipes = {}
    for _, recipe in ipairs(global.all_recipes.recipes) do
        -- Silly checks needed here for migration purposes
        if recipe.group.valid and recipe.subgroup.valid then table.insert(recipes, recipe) end
    end
    return create_object_tree(recipes)
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
        local type = item.proto.type
        local name = item.proto.name
        if table[type] == nil then table[type] = {} end
        -- Determine whether this item is used as a product at least once
        table[type][name] = table[type][name] or item.is_product
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
    -- Manually add the rocket-part item for the custom space recipe
    add_item(relevant_items, {proto=game["item_prototypes"]["rocket-part"], is_product=true})
    
    -- Adding all standard items minus the undesirable ones
    local undesirables = undesirable_items()
    for type, item_table in pairs(relevant_items) do
        for item_name, is_product in pairs(item_table) do
            if not undesirables[type][item_name] then
                local proto = game[type .. "_prototypes"][item_name]

                local hidden = false  -- "entity" types are never hidden
                if type == "item" then hidden = proto.has_flag("hidden")
                elseif type == "fluid" then hidden = proto.hidden end
                
                if not hidden or item_name == "rocket-part" then  -- exclude hidden items
                    local item = {
                        name = proto.name,
                        type = type,
                        sprite = type .. "/" .. proto.name,
                        localised_name = proto.localised_name,
                        ingredient_only = not is_product,
                        order = proto.order,
                        group = generate_group_table(proto.group),
                        subgroup = generate_group_table(proto.subgroup)
                    }

                    add_item_tooltip(item)
                    deep_insert_proto(all_items, "types", type, "items", item, true)
                end
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


-- Maps all items to the recipes that produce them ([item_type][item_name] = {[recipe_id] = true})
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

            map[product.type][product.name][recipe.id] = true
        end
    end
    
    return map
end


-- Returns the names of the item groups that shouldn't be included
function generator.undesirable_item_groups()
    return {
        item = {
            ["creative-mod_creative-tools"] = false,
            ["im-tools"] = false
        },
        recipe = {
            ["creative-mod_creative-tools"] = false,
            ["im-tools"] = false
        }
    }
end



-- Returns the names of the 'machines' that shouldn't be included
local function undesirable_machines()
    return {
        ["escape-pod-assembler"] = false,
        ["crash-site-assembling-machine-1-repaired"] = false,
        ["crash-site-assembling-machine-2-repaired"] = false
    }
end

-- Generates a table containing all machines for all categories
function generator.all_machines()
    local all_machines = {categories = {}, map = {}}
    
    local function generate_category_entry(category, proto)        
        -- If it is a miner, set speed to mining_speed so the machine_count-formula works out
        local speed = proto.crafting_categories and proto.crafting_speed or proto.mining_speed
        local energy = proto.energy_usage or proto.max_energy_usage or 0
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
            sprite = "entity/" .. proto.name,
            ingredient_limit = (proto.ingredient_count or 255),
            speed = speed,
            energy = energy,
            base_productivity = (proto.base_productivity or 0),
            allowed_effects = format_allowed_effects(proto.allowed_effects),
            module_limit = (proto.module_inventory_size or 0),
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

        -- Add mining machines
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
        
        -- Add offshore pumps
        elseif proto.fluid then
            local machine = generate_category_entry(proto.name, proto)
            machine.speed = 1  -- pumping speed included in the recipe product-amount
            deep_insert_proto(all_machines, "categories", proto.name, "machines", machine)
        end

        -- Add machines that produce steam
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


-- Returns the names of the 'modules' that shouldn't be included
local function undesirable_modules()
    return {
        ["seablock-mining-prod-module"] = false
    }
end


-- Generates a table containing all available modules
function generator.all_modules()
    local all_modules = {categories = {}, map = {}}
    local undesirables = undesirable_modules()

    for _, proto in pairs(game.item_prototypes) do
        if proto.type == "module" and undesirables[proto.name] == nil then
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


-- Returns the names of the 'beacons' that shouldn't be included
local function undesirable_beacons()
    return {
        ["seablock-mining-prod-provider"] = false
    }
end

-- Generates a table containing all available beacons
function generator.all_beacons()
    local all_beacons = {beacons = {}, map = {}}
    local undesirables = undesirable_beacons()

    for _, proto in pairs(game.entity_prototypes) do
        if proto.distribution_effectivity ~= nil and undesirables[proto.name] == nil then
            insert_proto(all_beacons, "beacons", {
                name = proto.name,
                localised_name = proto.localised_name,
                sprite = "entity/" .. proto.name,
                allowed_effects = format_allowed_effects(proto.allowed_effects),
                module_limit = proto.module_inventory_size,
                effectivity = proto.distribution_effectivity
            })
        end
    end

    return all_beacons
end
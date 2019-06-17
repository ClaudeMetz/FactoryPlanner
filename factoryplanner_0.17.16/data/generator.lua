generator = {}

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

-- Returns all standard recipes + custom mining recipes and space science recipe
function generator.all_recipes()
    local recipes = {}
    local undesirables = undesirable_recipes()

    local function mining_recipe()
        return {
            enabled = true,
            hidden = false,
            group = {name="intermediate_products", order="c"},
            subgroup = {name="mining", order="z"},
            valid = true
        }
    end
    
    for force_name, force in pairs(game.forces) do
        if recipes[force_name] == nil then 
            recipes[force_name] = {}
            -- Adding all standard recipes minus the undesirable ones
            for recipe_name, recipe in pairs(force.recipes) do
                -- Avoid any recipes that are undesirable or have no machine to produce them
                local category_id = global.all_machines.map[recipe.category]
                if undesirables[recipe_name] == nil and category_id ~= nil then
                    recipes[force_name][recipe_name] = recipe
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
                    -- Conforming to the real LuaRecipe prototype
                    recipe.prototype = { main_product = recipe.products[1] }

                    -- Add mining fluid, if required
                    if proto.mineable_properties.required_fluid then
                        table.insert(recipe.ingredients, {
                            type = "fluid",
                            name = proto.mineable_properties.required_fluid,
                            amount = proto.mineable_properties.fluid_amount
                        })
                        recipe.category = "complex-solid"
                    end

                    recipes[force_name][recipe.name] = recipe
                end
            end
            
            -- Adds a recipe for producing (vanilla) steam
            local recipe = mining_recipe()
            recipe.name = "impostor-steam"
            recipe.localised_name = {"fluid-name.steam"}   -- official locale
            recipe.category = "steam"
            recipe.order = "z"
            recipe.energy = 1
            recipe.ingredients = {{type="fluid", name="water", amount=60}}
            recipe.products = {{type="fluid", name="steam", amount=60}}
            recipe.prototype = { main_product = recipe.products[1] }
            recipes[force_name][recipe.name] = recipe
            
            -- Adds a convenient space science recipe
            recipes[force_name]["fp-space-science-pack"] = {
                name = "fp-space-science-pack",
                localised_name = {"item-name.space-science-pack"},  -- official locale
                category = "rocket-building",
                enabled = false,
                hidden = false,
                energy = 0,
                group = {name="intermediate-products", order="c"},
                subgroup = {name="science-pack", order="g"},
                order = "x[fp-space-science-pack]",
                ingredients = {
                    {type="item", name="rocket-part", amount=100},
                    {type="item", name="satellite", amount=1}
                },
                products = {{type="item", name="space-science-pack", amount=1000}},
                valid = true
            }
        end
    end

    return recipes
end


-- Returns all relevant items and fluids
function generator.all_items()
    local items = { index = {} }

    -- local function so generator. doesn't have this
    local function add_to_index(item_name, type)
        if items.index[item_name] == nil then
            items.index[item_name] = type
        else
            items.index[item_name] = "dupe"
        end
    end

    -- Create a table containing each item that has at least one recipe
    -- Use of the force "player" here is hack that will be fixed when recipe/item data is reworked
    -- (No need for undesirable item settings because removing the recipes removes the item)
    local craftable_products = {}
    for _, recipe in pairs(global.all_recipes["player"]) do
        for _, product in ipairs(recipe.products) do
            craftable_products[product.name] = true
        end
    end
    
    -- Adding all standard items minus the undesirable ones
    local types = {"item", "fluid"}
    for _, type in pairs(types) do
        items[type] = {}
        for item_name, item in pairs(game[type .. "_prototypes"]) do
            if global.all_fuels.map[item_name] or craftable_products[item_name] then
                items[type][item_name] = item
                add_to_index(item_name, type)
            end
        end
    end
    
    return items
end

-- Maps all items to the recipes that produce them ([item_name] = {[recipe_name] = true})
-- This optimizes the recipe filtering process for the recipe picker
function generator.item_recipe_map()
    local map = {
        item = {},
        fluid = {},
        entity = {}
    }

    -- Use of the force "player" here is hack that will be fixed when recipe/item data is reworked
    for recipe_name, recipe in pairs(global.all_recipes["player"]) do
        if recipe.valid then
            for _, product in ipairs(recipe.products) do
                if map[product.type][product.name] == nil then
                    map[product.type][product.name] = {}
                end
                map[product.type][product.name][recipe_name] = true
            end
        end
    end
    
    return map
end


-- Returns the names of the 'machines' that shouldn't be included
local function undesirable_machines()
    return {
        ["escape-pod-assembler"] = false
    }
end

-- Generates a table containing all machines for all categories
function generator.all_machines()
    local all_machines = nil

    local function add_machine(category_name, machine)
        if all_machines == nil then all_machines = {categories = {}, map = {}} end

        if all_machines.map[category_name] == nil then 
            table.insert(all_machines.categories, {machines = {}, map = {}})
            all_machines.map[category_name] = #all_machines.categories
            all_machines.categories[#all_machines.categories].id = #all_machines.categories
            all_machines.categories[#all_machines.categories].name = category_name
        end

        local category_entry = all_machines.categories[all_machines.map[category_name]]
        table.insert(category_entry.machines, machine)
        category_entry.map[machine.name] = #category_entry.machines
        machine.id = #category_entry.machines
        machine.category_id = category_entry.id

        return all_machines
    end
    
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
            localised_name = proto.localised_name,
            ingredient_limit = ingredient_limit,
            speed = speed,
            energy = energy,
            burner = burner
        }
        all_machines = add_machine(category, machine)
        return machine
    end

    local undesirables = undesirable_machines()
    for _, proto in pairs(game.entity_prototypes) do
        if proto.crafting_categories and proto.energy_usage ~= nil and undesirables[proto.name] == nil then
            for category, enabled in pairs(proto.crafting_categories) do
                if enabled then generate_category_entry(category, proto) end
            end

        -- Adds mining machines
        elseif proto.resource_categories then
            for category, enabled in pairs(proto.resource_categories) do
                -- Only supports solid mining recipes for now (no oil etc.)
                if enabled and category ~= "basic-fluid" then
                    generate_category_entry(category, proto)

                    -- Add separate category for mining with fluids that avoids the burner-miner
                    if category == "basic-solid" then
                        if not proto.burner_prototype then generate_category_entry("complex-solid", proto) end
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
                    end
                end
            end
        end
    end
    
    return all_machines
end


local function insert_object(t, name, object)
    table.insert(t[name], object)
    local id = #t[name]
    t[name][id].id = id
    t.map[object.name] = id
end


-- Generates a table containing all available transport belts
function generator.all_belts()
    local all_belts = {belts = {}, map = {}}
    for _, proto in pairs(game.entity_prototypes) do
        if proto.type == "transport-belt" then
            insert_object(all_belts, "belts", {
                name = proto.name,
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
            insert_object(all_fuels, "fuels", {
                name = proto.name,
                type = proto.type,
                localised_name = proto.localised_name,
                fuel_category = proto.fuel_category,
                fuel_value = proto.fuel_value
            })
        end
    end
    return all_fuels
end
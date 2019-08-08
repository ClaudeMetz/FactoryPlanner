data_util = {
    context = {},
    machine = {},
    item = {},
    base_data = {}
}

-- **** CONTEXT ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function data_util.context.create(player)
    return {
        factory = global.players[player.index].factory,
        subfactory = nil,
        floor = nil,
        line = nil
    }
end

-- Updates the context to match the newly selected subfactory
function data_util.context.set_subfactory(player, subfactory)
    local context = get_context(player)
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
    context.line = nil
end

-- Updates the context to match the newly selected floor
function data_util.context.set_floor(player, floor)
    local context = get_context(player)
    context.subfactory.selected_floor = floor
    context.floor = floor
    context.line = nil
end


-- **** MACHINES ****
-- Changes the preferred machine for the given category
function data_util.machine.set_default(player, category_id, machine_id)
    local preferences = get_preferences(player)
    local machine = global.all_machines.categories[category_id].machines[machine_id]
    preferences.default_machines.categories[category_id] = machine
    preferences.default_machines.map[machine.name] = category_id
end

-- Returns the default machine for the given category
function data_util.machine.get_default(player, category)
    return get_preferences(player).default_machines.categories[category.id]
end

-- Returns whether the given machine can produce the given recipe
function data_util.machine.is_applicable(machine_proto, recipe)
    local item_ingredients_count = 0
    -- Ingredient count does not include fluid ingredients
    for _, ingredient in pairs(recipe.proto.ingredients) do
        if ingredient.type == "item" then item_ingredients_count = item_ingredients_count + 1 end
    end
    return (item_ingredients_count <= machine_proto.ingredient_limit)
end


-- Changes the machine either to the given machine or moves it in the given direction
-- If neither machine or direction is given, it applies the default machine for the category
-- Returns false if no machine is applied because none can be found, true otherwise
function data_util.machine.change(player, line, machine, direction)
    -- Set the machine to the default one
    if machine == nil and direction == nil then
        local default_machine = data_util.machine.get_default(player, line.machine.category)
        return data_util.machine.change(player, line, default_machine, nil)

    -- Set machine directly
    elseif machine ~= nil and direction == nil then
        local machine = (machine.proto ~= nil) and machine or Machine.init_by_proto(machine)
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Returns false if no machine fits at all, so an appropriate error can be displayed
        if not data_util.machine.is_applicable(machine.proto, line.recipe) then
            return data_util.machine.change(player, line, machine, "positive")

        else
            line.machine = machine

            -- Adjust parent line
            if line.parent then  -- if no parent exists, nothing is overwritten anyway
                if line.subfloor then
                    Floor.get(line.subfloor, "Line", 1).machine = machine
                elseif line.id == 1 and line.parent.origin_line then
                    line.parent.origin_line.machine = machine
                end
            end

            -- Adjust modules (ie. trim them if needed)
            Line.trim_modules(line)
            Line.summarize_effects(line)

            -- Adjust beacon (ie. remove if machine does not allow beacons)
            if line.machine.proto.allowed_effects == nil then Line.set_beacon(line, nil) end

            return true
        end

    -- Bump machine in the given direction (takes given machine, if available)
    elseif direction ~= nil then
        local category, proto
        if machine ~= nil then
            if machine.proto then
                category = machine.category
                proto = machine.proto
            else
                category = global.all_machines.categories[global.all_machines.map[machine.category]]
                proto = machine
            end
        else
            category = line.machine.category
            proto = line.machine.proto
        end
        
        if direction == "positive" then
            if proto.id < #category.machines then
                local new_machine = category.machines[proto.id + 1]
                return data_util.machine.change(player, line, new_machine, nil)
            else
                return false
            end
        else  -- direction == "negative"
            if proto.id > 1 then
                local new_machine = category.machines[proto.id - 1]
                return data_util.machine.change(player, line, new_machine, nil)
            else
                return false            
            end
        end
    end
end


-- **** BASE DATA ****
-- Creates the default structure for default_machines
function data_util.base_data.default_machines(table)
    local default_machines = {categories = {}, map = {}}
    for category_id, category in pairs(table.all_machines.categories) do
        default_machines.categories[category_id] = category.machines[1]
        default_machines.map[category.name] = category_id
    end
    return default_machines
end

-- Returns the default preferred belt
function data_util.base_data.preferred_belt(table)
    return table.all_belts.belts[1]
end

-- Returns the default preferred belt (tries to choose coal)
function data_util.base_data.preferred_fuel(table)
    local fuels = table.all_fuels
    if fuels.map["coal"] then
        return fuels.fuels[fuels.map["coal"]]
    else
        return fuels.fuels[1]
    end
end

-- Returns the default preferred beacon
function data_util.base_data.preferred_beacon(table)
    return table.all_beacons.beacons[1]
end


-- **** MISC ****
-- Updates validity of every class specified by the classes parameter
function data_util.run_validation_updates(parent, classes)
    local valid = true
    for type, class in pairs(classes) do
        if not Collection.update_validity(parent[type], class) then
            valid = false
        end
    end
    return valid
end

-- Tries to repair every specified class, deletes them if this is unsuccessfull
function data_util.run_invalid_dataset_repair(player, parent, classes)
    for type, class in pairs(classes) do
        Collection.repair_invalid_datasets(parent[type], player, class, parent)
    end
end


-- Determines the actual amount of items that a recipe_product produces
function data_util.determine_product_amount(base_product)
    if base_product.amount_max ~= nil and base_product.amount_min ~= nil then
        return ((base_product.amount_max + base_product.amount_min) / 2) * base_product.probability
    elseif base_product.probability ~= nil then
        return base_product.amount * base_product.probability
    else
        return base_product.amount
    end
end

-- Determines the actual amount of items that a recipe_product produces
function data_util.determine_machine_count(player, subfactory, line, machine_proto, production_ratio)
    local mining_prod = data_util.determine_mining_productivity(player, subfactory, machine_proto)
    local machine_prod_ratio = production_ratio / (1 + line.total_effects.productivity + mining_prod)
    local machine_speed = machine_proto.speed + (machine_proto.speed * line.total_effects.speed)
    return (machine_prod_ratio / (machine_speed / line.recipe.proto.energy)) / subfactory.timescale
end

-- Determines the amount of energy the given machine will consume
function data_util.determine_energy_consumption(machine, machine_count, total_effects)
    local energy_consumption = machine_count * (machine.proto.energy * 60)
    return energy_consumption + (energy_consumption * math.max(total_effects.consumption, -0.8))
end

-- Determines the amount of fuel needed in the given context (ec = energy_consumption)
function data_util.determine_fuel_amount(ec, subfactory, fuel_proto, burner)
    return ((ec / burner.effectivity) / fuel_proto.fuel_value) * subfactory.timescale
end

-- Determines whether mining prod applies, and returns it's value (returns 0 otherwise)
function data_util.determine_mining_productivity(player, subfactory, machine_proto)
    if machine_proto.category == "basic-solid" then  -- meaning (solid) mining recipes
        return ((subfactory.mining_productivity ~= nil) and 
          subfactory.mining_productivity or player.force.mining_drill_productivity_bonus) / 100
    else
        return 0
    end
end


-- Logs given table shallowly, excluding the parent attribute
function data_util.gen_log(table)
    if table == nil then
        return "nil"
    else
        local s = "\n{\n"
        for name, value in pairs(table) do
            if type(value) == "table" then
                s = s .. "  " .. name .. " = table\n"
            else
                s = s .. "  " .. name .. " = " .. tostring(value) .. "\n"
            end
        end
        s = s .. "}"
        return s
    end
end


-- Following are a couple helper functions for populating (sub)factories
-- Adds all given products to the given subfactory (table definition see above)
local function add_products(subfactory, products)
    for _, product in ipairs(products) do
        local item = TopLevelItem.init_by_item(product, "Product", product.amount, product.required_amount)
        Subfactory.add(subfactory, item)
    end
end

-- Adds all given recipes to the floor, recursively calling itself in case of subfloors
-- Needs an appropriately formated recipes table
local function construct_floor(player, floor, recipes)
    -- Tries to find a module with the given name in all module categories
    local function find_module(name)
        for _, category in pairs(global.all_modules.categories) do
            for _, module in pairs(category.modules) do
                if module.name == name then
                    return module
                end
            end
        end
    end

    -- Adds a line containing the given recipe to the current floor
    local function add_line(recipe_data)
        -- Create recipe line
        local recipe = Recipe.init_by_id(global.all_recipes.map[recipe_data.name])
        local category = global.all_machines.categories[global.all_machines.map[recipe.proto.category]]
        local machine = category.machines[category.map[recipe_data.machine]]
        local line = Floor.add(floor, Line.init(player, recipe, machine))

        -- Optionally, add modules
        if recipe_data.modules ~= nil then
            for _, module in pairs(recipe_data.modules) do
                Line.add(line, Module.init_by_proto(find_module(module.name), module.amount))
            end
        end

        -- Optionally, add beacon
        if recipe_data.beacon ~= nil then
            local beacon_data = recipe_data.beacon.beacon
            local beacon_proto = global.all_beacons.beacons[global.all_beacons.map[beacon_data.name]]

            local module_data = recipe_data.beacon.module
            local module_proto = find_module(module_data.name)

            local beacon = Beacon.init_by_protos(beacon_proto, beacon_data.amount, module_proto, module_data.amount)
            Line.set_beacon(line, beacon)
        end

        return line
    end
    
    for _, recipe_data in ipairs(recipes) do
        if #recipe_data == 0 then  -- Meaning this isn't a whole subfloor
            add_line(recipe_data)
        else
            -- First, it adds the top-level line to the floor
            local line = add_line(recipe_data[1])
            local subfloor = Floor.init(line)
            line.subfloor = Subfactory.add(floor.parent, subfloor)
            
            -- Then, it creates a subfloor with the remaining recipes
            table.remove(recipe_data, 1)
            construct_floor(player, line.subfloor, recipe_data)
        end
    end
end


-- Initiates the data table with some values for development purposes
function data_util.run_dev_config(player)
    if devmode then
        local context = get_context(player)
        local factory = context.factory

        -- Subfactories
        local subfactory = Factory.add(factory, Subfactory.init("", {type="item", name="iron-plate"}))
        data_util.context.set_subfactory(player, subfactory)
        Factory.add(factory, Subfactory.init("Beta", nil))
        Factory.add(factory, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}))

        -- Products
        local products = {
            {
                name = "electronic-circuit",
                type = "item",
                amount = 0,
                required_amount = 400
            }--[[,
            {
                name = "uranium-235",
                type = "item",
                amount = 0,
                required_amount = 10
            } ]]
        }
        add_products(subfactory, products)
        
        -- Floors
        local recipes = {
            {
                name="electronic-circuit",
                machine="assembling-machine-2"
            }
        }
        construct_floor(player, context.floor, recipes)
    end
end

-- Adds an example subfactory for new users to explore (returns that subfactory)
function data_util.add_example_subfactory(player)
    local context = get_context(player)
    local factory = context.factory
    
    local subfactory = Factory.add(factory, Subfactory.init("Example", {type="item", name="automation-science-pack"}))
    data_util.context.set_subfactory(player, subfactory)
    
    -- Products
    local products = {
        {
            name = "automation-science-pack",
            type = "item",
            amount = 0,
            required_amount = 60
        },
        {
            name = "logistic-science-pack",
            type = "item",
            amount = 0,
            required_amount = 60
        },
        {
            name = "military-science-pack",
            type = "item",
            amount = 0,
            required_amount = 60
        }
    }
    add_products(subfactory, products)
    
    -- Recipes    
    -- This table describes the desired hierarchical structure of the subfactory
    -- (Order is important; sub-tables represent their own subfloors (recursively))
    local recipes = {
        {
            name="automation-science-pack",
            machine="assembling-machine-2",
            modules={{name="speed-module", amount=2}}
        },
        {
            {name="logistic-science-pack", machine="assembling-machine-2"},
            {name="transport-belt", machine="assembling-machine-1"},
            {name="inserter", machine="assembling-machine-1"}
        },
        {
            {
                name="military-science-pack",
                machine="assembling-machine-2",
                modules={{name="productivity-module-2", amount=2}},
                beacon={beacon={name="beacon", amount=8}, module={name="speed-module-2", amount=2}}
            },
            {
                name="grenade",
                machine="assembling-machine-2",
                modules={{name="speed-module-3", amount=2}}
            },
            {name="stone-wall", machine="assembling-machine-1"},
            {name="piercing-rounds-magazine", machine="assembling-machine-1"},
            {name="firearm-magazine", machine="assembling-machine-1"}
        }, 
        {name="iron-gear-wheel", machine="assembling-machine-1"},
        {
            {name="electronic-circuit", machine="assembling-machine-1"},
            {name="copper-cable", machine="assembling-machine-1"}
        }, 
        {name="steel-plate", machine="steel-furnace"},
        {name="stone-brick", machine="steel-furnace"},
        {
            name="impostor-stone",
            machine="electric-mining-drill",
            modules={{name="speed-module-2", amount=1}, {name="effectivity-module-2", amount=1}}
        },
        {
            name="impostor-coal",
            machine="electric-mining-drill",
            beacon={beacon={name="beacon", amount=6}, module={name="speed-module-3", amount=2}}
        }
    }
    construct_floor(player, context.floor, recipes)
    
    return subfactory
end
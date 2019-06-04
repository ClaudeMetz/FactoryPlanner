data_util = {
    context = {},
    machines = {}
}

-- **** CONTEXT ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function data_util.context.create(player)
    return {
        subfactory = nil,
        floor = nil,
        line = nil
    }
end

-- Updates the context to match the newly selected subfactory
function data_util.context.set_subfactory(player, subfactory)
    local context = global.players[player.index].context
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
    context.line = nil
end

-- Updates the context to match the newly selected floor
function data_util.context.set_floor(player, floor)
    local context = global.players[player.index].context
    context.subfactory.selected_floor = floor
    context.floor = floor
    context.line = nil
end


-- **** MACHINES ****
-- Updates default machines for the given player, restoring previous settings
function data_util.machines.update_default(player)
    local old_defaults = global.players[player.index].default_machines
    local new_defaults = {}

    for category, data in pairs(global.all_machines) do
        if old_defaults[category] ~= nil and data.machines[old_defaults[category]] ~= nil then
            new_defaults[category] = old_defaults[category]
        else
            new_defaults[category] = data.machines[data.order[1]].name
        end
    end
    
    global.players[player.index].default_machines = new_defaults
end

-- Changes the preferred machine for the given category
function data_util.machines.set_default(player, category, name)
    global.players[player.index].default_machines[category] = name
end

-- Returns the default machine for the given category
function data_util.machines.get_default(player, category)
    local defaults = global.players[player.index].default_machines
    return global.all_machines[category].machines[defaults[category]]
end


-- **** MISC ****
-- Updates validity of every class specified by the classes parameter
function data_util.run_validation_updates(player, parent, classes)
    local valid = true
    for type, class in pairs(classes) do
        if not Collection.update_validity(parent[type], player, class) then
            valid = false
        end
    end
    return valid
end

-- Removes all invalid datasets of every class specified by the classes parameter
function data_util.run_invalid_dataset_removal(player, parent, classes, attempt_repair)
    for type, class in pairs(classes) do
        Collection.remove_invalid_datasets(parent[type], player, parent, attempt_repair)
    end
end

-- Following are a couple helper functions for populating (sub)factories
-- Adds all given products to the given subfactory (table definition see above)
local function add_products(subfactory, products)
    for _, product in ipairs(products) do
        local dataset = Subfactory.add(subfactory, Item.init({name=product.name, type=product.type}, nil, "Product", product.amount))
        dataset.required_amount = product.required_amount
    end
end

-- Adds all given recipes to the floor, recursively calling itself in case of subfloors
-- Needs an appropriately formated recipes table (see definitions above)
local function construct_floor(player, floor, recipes)
    -- Adds a line containing the given recipe to the current floor
    local function add_line(recipe_data)
        local recipe = global.all_recipes[player.force.name][recipe_data.recipe]
        local machine_category = global.all_machines[recipe.category]
        local machine = machine_category.machines[machine_category.order[recipe_data.machine]]
        return Floor.add(floor, Line.init(recipe, machine))
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
    if global.devmode then
        local player_table = global.players[player.index]
        local factory = player_table.factory

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
            },
            {
                name = "heavy-oil",
                type = "fluid",
                amount = 0,
                required_amount = 100
            },
            {
                name = "uranium-235",
                type = "item",
                amount = 0,
                required_amount = 10
            },
            {
                name = "steam",
                type = "fluid",
                amount = 0,
                required_amount = 100
            }
        }
        add_products(subfactory, products)

        -- Floors
        local recipes = {
            {recipe="electronic-circuit", machine=1}
        }
        construct_floor(player, player_table.context.floor, recipes)
    end
end

-- Adds an example subfactory for new users to explore (returns that subfactory)
function data_util.add_example_subfactory(player)
    local player_table = global.players[player.index]
    local factory = player_table.factory
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
        {recipe="automation-science-pack", machine=2},
        {
            {recipe="logistic-science-pack", machine=2},
            {recipe="transport-belt", machine=1},
            {recipe="inserter", machine=1}
        },
        {
            {recipe="military-science-pack", machine=2},
            {recipe="grenade", machine=2},
            {recipe="stone-wall", machine=1},
            {recipe="piercing-rounds-magazine", machine=1},
            {recipe="firearm-magazine", machine=1}
        }, 
        {recipe="iron-gear-wheel", machine=1},
        {
            {recipe="electronic-circuit", machine=1},
            {recipe="copper-cable", machine=1}
        }, 
        {recipe="steel-plate", machine=2},
        {recipe="stone-brick", machine=2},
        {recipe="impostor-stone", machine=2},
        {recipe="impostor-coal", machine=2}
    }
    construct_floor(player, player_table.context.floor, recipes)
    
    return subfactory
end
data_util = {
    context = {},
    machines = {},
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
function data_util.machines.set_default(player, category_id, machine_id)
    local preferences = get_preferences(player)
    preferences.default_machines.machines[category_id] = machine_id
    local machine = global.all_machines.categories[category_id].machines[machine_id]
    preferences.default_machines.map[machine.name] = category_id
end

-- Returns the default machine for the given category
function data_util.machines.get_default(player, category_id)
    return get_preferences(player).default_machines.machines[category_id]
end

-- Returns whether the given machine can produce the given recipe (ingredient limit)
function data_util.machines.is_applicable(player, category_id, machine_id, recipe_name)
    local machine = global.all_machines.categories[category_id].machines[machine_id]
    local recipe = global.all_recipes[player.force.name][recipe_name]
    return (#recipe.ingredients <= machine.ingredient_limit)
end

-- Changes the machine either to the given machine or moves it in the given direction
-- If neither machine_id or direction is given, it applies the default machine for the category
function data_util.machines.change_machine(player, line, machine_id, direction)
    -- Set the machine to the default one
    if machine_id == nil and direction == nil then
        local default_machine_id = data_util.machines.get_default(player, line.category_id)
        data_util.machines.change_machine(player, line, default_machine_id, nil)

    -- Set machine directly
    elseif machine_id ~= nil and direction == nil then
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Probably crashes if no machine fits at all (unlikely)
        if not data_util.machines.is_applicable(player, line.category_id, machine_id, line.recipe_name) then
            data_util.machines.change_machine(player, line, machine_id, "positive")

        else
            line.machine_id = machine_id
            if line.parent then  -- if no parent exists, nothing is overwritten anyway
                if line.subfloor then
                    Floor.get(line.subfloor, "Line", 1).machine_id = machine_id
                elseif line.id == 1 and line.parent.origin_line then
                    line.parent.origin_line.machine_id = machine_id
                end
            end
        end

    -- Bump machine in the given direction (takes given machine, if available)
    elseif direction ~= nil then
        machine_id = machine_id or line.machine_id
        local category = global.all_machines.categories[line.category_id]
        if direction == "positive" then
            if machine_id < #category.machines then
                data_util.machines.change_machine(player, line, machine_id + 1, nil)
            end
        else  -- direction == "negative"
            if machine_id > 1 then
                data_util.machines.change_machine(player, line, machine_id - 1, nil)
            end
        end
    end
end


-- **** BASE DATA ****
-- Creates the default structure for default_machines
function data_util.base_data.default_machines()
    local default_machines = {machines = {}, map = {}}
    for category_id, category in ipairs(global.all_machines.categories) do
        default_machines.machines[category_id] = category.machines[1].id
        default_machines.map[category.name] = category_id
    end
    return default_machines
end

-- Returns the default preferred belt
function data_util.base_data.preferred_belt()
    return global.all_belts.belts[1].id
end

-- Returns the default preferred belt (tries to choose coal)
function data_util.base_data.preferred_fuel()
    if global.all_fuels.map["coal"] then
        return global.all_fuels.map["coal"]
    else
        return global.all_fuels.fuels[1].id
    end
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
        local category_id = global.all_machines.map[recipe.category]
        local machine = global.all_machines.categories[category_id].machines[recipe_data.machine_id]
        return Floor.add(floor, Line.init(player, recipe, machine))
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
                name = "grenade",
                type = "item",
                amount = 0,
                required_amount = 100
            },
            {
                name = "iron-plate",
                type = "item",
                amount = 0,
                required_amount = 100
            }
        }
        add_products(subfactory, products)

        -- Floors
        local recipes = {
            --{recipe="electronic-circuit", machine_id=1}
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
        {recipe="automation-science-pack", machine_id=2},
        {
            {recipe="logistic-science-pack", machine_id=2},
            {recipe="transport-belt", machine_id=1},
            {recipe="inserter", machine_id=1}
        },
        {
            {recipe="military-science-pack", machine_id=2},
            {recipe="grenade", machine_id=2},
            {recipe="stone-wall", machine_id=1},
            {recipe="piercing-rounds-magazine", machine_id=1},
            {recipe="firearm-magazine", machine_id=1}
        }, 
        {recipe="iron-gear-wheel", machine_id=1},
        {
            {recipe="electronic-circuit", machine_id=1},
            {recipe="copper-cable", machine_id=1}
        }, 
        {recipe="steel-plate", machine_id=2},
        {recipe="stone-brick", machine_id=2},
        {recipe="impostor-stone", machine_id=2},
        {recipe="impostor-coal", machine_id=2}
    }
    construct_floor(player, context.floor, recipes)
    
    return subfactory
end
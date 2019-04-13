data_util = {
    context = {},
    machines = {}
}

-- **** CONTEXT ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function data_util.context.create()
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
-- Initiates the data table with some values for development purposes
function data_util.run_dev_config(player)
    if global.devmode then
        local player_table = global.players[player.index]
        local factory = player_table.factory

        local subfactory = Factory.add(factory, Subfactory.init("", {type="item", name="iron-plate"}))
        Factory.add(factory, Subfactory.init("Beta", nil))
        Factory.add(factory, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}))
        data_util.context.set_subfactory(player, subfactory)

        local prod1 = Subfactory.add(subfactory, Item.init({name="electronic-circuit", type="item"}, nil, "Product", 0))
        prod1.required_amount = 400
        local prod2 = Subfactory.add(subfactory, Item.init({name="heavy-oil", type="fluid"}, nil, "Product", 0))
        prod2.required_amount = 100
        local prod3 = Subfactory.add(subfactory, Item.init({name="uranium-235", type="item"}, nil, "Product", 0))
        prod3.required_amount = 10

        local floor = Subfactory.get(subfactory, "Floor", 1)
        local recipe = global.all_recipes[player.force.name]["electronic-circuit"]
        local machine = data_util.machines.get_default(player, recipe.category)
        Floor.add(floor, Line.init(recipe, machine))
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

    for _, product in ipairs(products) do
        local dataset = Subfactory.add(subfactory, Item.init({name=product.name, type=product.type}, nil, "Product", product.amount))
        dataset.required_amount = product.required_amount
    end
    

    -- Recipes
    -- Adds all given recipes to the floor, recursively calling itself in case of subfloors
    local function construct_floor(floor, recipes)
        -- Adds a line containing the given recipe to the current floor
        local function add_line(recipe_name)
            local recipe = global.all_recipes[player.force.name][recipe_name]
            local machine = data_util.machines.get_default(player, recipe.category)
            return Floor.add(floor, Line.init(recipe, machine))
        end
        
        for _, recipe_name in ipairs(recipes) do
            if type(recipe_name) == "table" then
                -- First, it adds the top-level line to the floor, then creates a subfloor with the remaining recipes
                local line = add_line(recipe_name[1])
                local subfloor = Floor.init(line)
                line.subfloor = Subfactory.add(subfactory, subfloor)
                
                table.remove(recipe_name, 1)
                construct_floor(line.subfloor, recipe_name)
            else
                add_line(recipe_name)
            end
        end
    end
    
    -- This table describes the desired hierarchical structure of the subfactory
    -- (Order is important; sub-tables represent their own subfloors (recursively))
    local recipes = {
        "automation-science-pack",
        {
            "logistic-science-pack",
            "transport-belt",
            "inserter"
        },
        {
            "military-science-pack",
            "grenade",
            "stone-wall",
            "piercing-rounds-magazine",
            "firearm-magazine"
        }, 
        "iron-gear-wheel",
        {
            "electronic-circuit",
            "copper-cable"
        }, 
        "steel-plate",
        "stone-brick",
        "impostor-stone",
        "impostor-coal"
    }

    construct_floor(player_table.context.floor, recipes)

    
    return subfactory
end
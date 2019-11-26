-- Contains the methods and definitions to generate subfactories by code
constructor = {}

-- Following are a couple helper functions for populating (sub)factories
-- Adds all given products to the given subfactory (table definition see above)
local function add_products(subfactory, products)
    for _, product in ipairs(products) do
        local item = Item.init_by_item(product, "Product", 0, (product.required_amount or 0))
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
        local production_type = recipe_data.production_type or "produce"
        local recipe = Recipe.init_by_id(global.all_recipes.map[recipe_data.name], production_type)
        local category = global.all_machines.categories[global.all_machines.map[recipe.proto.category]]
        local machine = category.machines[category.map[recipe_data.machine]]
        local line = Floor.add(floor, Line.init(player, recipe, machine))

        -- Optionally, add modules
        if recipe_data.modules ~= nil then
            for _, module in pairs(recipe_data.modules) do
                Line.add(line, Module.init_by_proto(find_module(module.name), module.amount))
            end
        end

        -- Optionally, add beacons
        if recipe_data.beacons ~= nil then
            local beacon_data = recipe_data.beacons.beacon
            local beacon_proto = global.all_beacons.beacons[global.all_beacons.map[beacon_data.name]]

            local module_data = recipe_data.beacons.module
            local module_proto = find_module(module_data.name)

            local beacon = Beacon.init_by_protos(beacon_proto, beacon_data.amount, module_proto, module_data.amount,
              recipe_data.beacons.total_amount)
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
function constructor.dev_config(player)
    if devmode then
        local context = get_context(player)
        local factory = context.factory

        -- Subfactories
        local subfactory = Factory.add(factory, Subfactory.init("", {type="item", name="iron-plate"}, "one_minute"))
        data_util.context.set_subfactory(player, subfactory)
        Factory.add(factory, Subfactory.init("Beta", nil, "one_minute"))
        Factory.add(factory, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}, "one_minute"))

        -- Products
        local products = {
            {
                name = "electronic-circuit",
                type = "item",
                required_amount = 400
            },
            {
                name = "uranium-235",
                type = "item",
                required_amount = 10
            },
            {
                name = "iron-ore",
                type = "item",
                required_amount = 100
            },
            {
                name = "light-oil",
                type = "fluid",
                required_amount = 250
            },
            {
                name = "rocket-part",
                type = "item",
                required_amount = 540
            }
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
function constructor.example_subfactory(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local factory = player_table.factory
    
    -- Always add the example subfactory as a non-archived one
    local subfactory = Factory.add(factory, Subfactory.init("Example", 
      {type="item", name="production-science-pack"}, "one_minute"))
    factory.selected_subfactory = subfactory
    data_util.context.set_factory(player, factory)
    ui_state.archive_open = false
    
    -- Products
    local products = {
        {
            name = "production-science-pack",
            type = "item",
            required_amount = 180
        }
    }
    add_products(subfactory, products)
    
    -- Recipes    
    -- This table describes the desired hierarchical structure of the subfactory
    -- (Order is important; sub-tables represent their own subfloors (recursively))
    local recipes = {
        {
            {
                name="production-science-pack",
                machine="assembling-machine-3",
                modules={{name="productivity-module-3", amount=4}},
                beacons={beacon={name="beacon", amount=8}, module={name="speed-module-3", amount=2}}
            },
            {
                name="rail",
                machine="assembling-machine-2"
            },
            {
                name="iron-stick",
                machine="assembling-machine-2"
            },
            {
                name="electric-furnace",
                machine="assembling-machine-2"
            },
            {
                name="productivity-module",
                machine="assembling-machine-2",
                modules={{name="speed-module-2", amount=2}},
            }
        },
        {
            name="advanced-circuit",
            machine="assembling-machine-3",
            modules={{name="productivity-module-3", amount=4}},
            beacons={beacon={name="beacon", amount=8}, module={name="speed-module-3", amount=2}}
        },
        {
            name="electronic-circuit",
            machine="assembling-machine-2"
        },
        {
            name="copper-cable",
            machine="assembling-machine-2"
        },
        {
            name="steel-plate",
            machine="electric-furnace",
            modules={{name="productivity-module-3", amount=2}},
            beacons={beacon={name="beacon", amount=8}, module={name="speed-module-3", amount=2}}
        },
        {
            name="stone-brick",
            machine="electric-furnace"
        },
        {
            name="impostor-stone",
            machine="electric-mining-drill",
            modules={{name="productivity-module-2", amount=2}, {name="speed-module-2", amount=1}}
        }
    }
    construct_floor(player, ui_state.context.floor, recipes)
    
    return subfactory
end
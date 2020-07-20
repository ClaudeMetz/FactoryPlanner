-- Contains the methods and definitions to generate subfactories by code
builder = {}

-- ** LOCAL UTIL **
-- Following are a couple helper functions for populating (sub)factories
-- Adds all given products to the given subfactory (table definition see above)
local function add_products(player, subfactory, products)
    for _, product in ipairs(products) do
        -- Amounts will depend on the value of the belts/lanes-setting
        local req_amount = {
            defined_by = product.defined_by,
            amount = product.amount
        }

        -- The timescale is implicitly the one defined for the subfactory
        if product.defined_by ~= "amount" then
            -- Convert definitions by belt to lanes if necessary
            if get_settings(player).belts_or_lanes == "lanes" then
                req_amount.defined_by = "lanes"
                req_amount.amount = req_amount.amount * 2
            end

            local belt_proto = global.all_belts.belts[global.all_belts.map[product.belt_name]]
            req_amount.belt_proto = belt_proto
        end

        local prod = {name=product.name, type=product.type}
        local item = Item.init_by_item(prod, "Product", 0, req_amount)
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
        local machine_proto = category.machines[category.map[recipe_data.machine]]

        local line = Floor.add(floor, Line.init(recipe, true))
        Line.change_machine(line, player, machine_proto, nil)

        -- Optionally, add modules
        if recipe_data.modules ~= nil then
            for _, module in pairs(recipe_data.modules) do
                Machine.add(line.machine, Module.init_by_proto(find_module(module.name), module.amount))
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
            Subfactory.add(floor.parent, subfloor)

            -- Then, it creates a subfloor with the remaining recipes
            table.remove(recipe_data, 1)
            construct_floor(player, subfloor, recipe_data)
        end
    end
end


-- ** TOP LEVEL **
-- Initiates the data table with some values for development purposes
function builder.dev_config(player)
    if devmode then
        get_preferences(player).tutorial_mode = false

        local context = get_context(player)
        local factory = context.factory

        -- Subfactories
        local subfactory = Factory.add(factory, Subfactory.init("", {type="item", name="iron-plate"},
          "one_minute", true))
        ui_util.context.set_subfactory(player, subfactory)

        Factory.add(factory, Subfactory.init("Beta", nil, "one_minute", true))
        Factory.add(factory, Subfactory.init("Gamma", {type="item", name="electronic-circuit"}, "one_minute", true))

        -- Products
        local products = {
            {
                name = "electronic-circuit",
                type = "item",
                defined_by = "amount",
                amount = 400
            },
            {
                name = "uranium-235",
                type = "item",
                defined_by = "amount",
                amount = 10
            },
            {
                name = "iron-ore",
                type = "item",
                defined_by = "belts",
                amount = 0.5,
                belt_name = "transport-belt"
            },
            {
                name = "light-oil",
                type = "fluid",
                defined_by = "amount",
                amount = 250
            },
            {
                name = "steam",
                type = "fluid",
                defined_by = "amount",
                amount = 1000
            }
        }
        add_products(player, subfactory, products)

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
function builder.example_subfactory(player)
    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local factory = player_table.factory

    -- Always add the example subfactory as a non-archived one
    local subfactory = Factory.add(factory, Subfactory.init("Example",
      {type="item", name="production-science-pack"}, "one_minute", true))
    factory.selected_subfactory = subfactory
    ui_util.context.set_factory(player, factory)
    ui_state.flags.archive_open = false

    -- Products
    local products = {
        {
            name = "production-science-pack",
            type = "item",
            defined_by = "amount",
            amount = 180
        }
    }
    add_products(player, subfactory, products)

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
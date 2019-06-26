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

-- Returns whether the given machine can produce the given recipe (ingredient limit)
function data_util.machine.is_applicable(machine, recipe)
    return (#recipe.proto.ingredients <= machine.proto.ingredient_limit)
end

-- Changes the machine either to the given machine or moves it in the given direction
-- If neither machine or direction is given, it applies the default machine for the category
function data_util.machine.change(player, line, machine, direction)
    -- Set the machine to the default one
    if machine == nil and direction == nil then
        local default_machine = data_util.machine.get_default(player, line.machine.category)
        data_util.machine.change(player, line, default_machine, nil)

    -- Set machine directly
    elseif machine ~= nil and direction == nil then
        local machine = (machine.proto ~= nil) and machine or Machine.init_by_proto(machine)
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Crashes if no machine fits at all (unlikely)
        if not data_util.machine.is_applicable(machine, line.recipe) then
            data_util.machine.change(player, line, machine, "positive")

        else
            line.machine = machine
            if line.parent then  -- if no parent exists, nothing is overwritten anyway
                if line.subfloor then
                    Floor.get(line.subfloor, "Line", 1).machine = machine
                elseif line.id == 1 and line.parent.origin_line then
                    line.parent.origin_line.machine = machine
                end
            end
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
                data_util.machine.change(player, line, new_machine, nil)
            end
        else  -- direction == "negative"
            if proto.id > 1 then
                local new_machine = category.machines[proto.id - 1]
                data_util.machine.change(player, line, new_machine, nil)
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

-- Returns the number to put on an item button according to the current view
function data_util.calculate_item_button_number(player_table, view, amount, type)
    local number = nil

    local timescale = player_table.ui_state.context.subfactory.timescale
    if view == nil then
        local view_state = player_table.ui_state.view_state
        -- If the view state hasn't been initialised yet, assume the default
        -- (This gets re-run when the view state gets initialised)
        if view_state == nil then return amount end
        view = view_state[view_state.selected_view_id]
    end

    if view.name == "items_per_timescale" then
        number = amount
    elseif view.name == "belts_or_lanes" and type ~= "fluid" then
        local throughput = player_table.preferences.preferred_belt.throughput
        local divisor = (player_table.settings.belts_or_lanes == "Belts") and throughput or (throughput / 2)
        number = amount / divisor / timescale
    elseif view.name == "items_per_second" then
        number = amount / timescale
    end

    return number  -- number might be nil here
end


-- Logs given table shallowly, excluding the parent attribute
function data_util.log(table)
    local s = "\n{\n"
    for name, value in pairs(table) do
        if type(value) == "table" then
            s = s .. "  " .. name .. " = table\n"
        else
            s = s .. "  " .. name .. " = " .. tostring(value) .. "\n"
        end
    end
    s = s .. "}"
    log(s)
end


-- Following are a couple helper functions for populating (sub)factories
-- Adds all given products to the given subfactory (table definition see above)
local function add_products(subfactory, products)
    for _, product in ipairs(products) do
        local item = Item.init_by_item(product, "Product", product.amount)
        local dataset = Subfactory.add(subfactory, item)
        dataset.required_amount = product.required_amount
    end
end

-- Adds all given recipes to the floor, recursively calling itself in case of subfloors
-- Needs an appropriately formated recipes table (see definitions above)
local function construct_floor(player, floor, recipes)
    -- Adds a line containing the given recipe to the current floor
    local function add_line(recipe_data)
        local recipe = Recipe.init(global.all_recipes.map[recipe_data.recipe])
        local category = global.all_machines.categories[global.all_machines.map[recipe.proto.category]]
        local machine = category.machines[category.map[recipe_data.machine]]
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
            }--[[ ,
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
            } ]]
        }
        add_products(subfactory, products)
        
        -- Floors
        local recipes = {
            {recipe="electronic-circuit", machine="assembling-machine-1"}
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
        {recipe="automation-science-pack", machine_id="assembling-machine-2"},
        {
            {recipe="logistic-science-pack", machine_id="assembling-machine-2"},
            {recipe="transport-belt", machine_id="assembling-machine-1"},
            {recipe="inserter", machine_id="assembling-machine-1"}
        },
        {
            {recipe="military-science-pack", machine_id="assembling-machine-2"},
            {recipe="grenade", machine_id="assembling-machine-2"},
            {recipe="stone-wall", machine_id="assembling-machine-1"},
            {recipe="piercing-rounds-magazine", machine_id="assembling-machine-1"},
            {recipe="firearm-magazine", machine_id="assembling-machine-1"}
        }, 
        {recipe="iron-gear-wheel", machine_id="assembling-machine-1"},
        {
            {recipe="electronic-circuit", machine_id="assembling-machine-1"},
            {recipe="copper-cable", machine_id="assembling-machine-1"}
        }, 
        {recipe="steel-plate", machine_id="steel-furnace"},
        {recipe="stone-brick", machine_id="steel-furnace"},
        {recipe="impostor-stone", machine_id="electric-mining-drill"},
        {recipe="impostor-coal", machine_id="electric-mining-drill "}
    }
    construct_floor(player, context.floor, recipes)
    
    return subfactory
end
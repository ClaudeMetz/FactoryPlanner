-- Represents an (assembly) line, uses a single recipe
Line = {}

function Line.init(player, recipe, skip_item_init)
    local recipe_category = recipe.category
    local recipe_energy = recipe.energy
    if recipe_category == "basic-solid" then
        -- Set recipe_energy to mining time for the custom mining recipes
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == "entity" then
                recipe_energy = recipe.mining_time
            end
        end

        -- Detect recipes that require fluids to mine
        if #recipe.ingredients > 1 then recipe_category = "complex-solid" end
    end
    local default_machine = data_util.get_default_machine(player, recipe_category)

    local line = {
        id = 0,
        recipe_name = recipe.name,
        recipe_category = recipe_category,
        recipe_energy = recipe_energy,
        production_ratio = 0,
        percentage = 100,
        machine_name = default_machine.name,
        machine_count = 0,
        energy_consumption = 0,  -- in Watt
        valid = true,
        gui_position = 0,
        type = "Line"
    }

    -- Byproducts are included in products and differentiate by their kind-attribute
    -- for performance reasons (LineItems only, not the aggregate)
    local categories = {"products", "ingredients"}
    for _, category in pairs(categories) do
        line[category] = {
            datasets = {},
            index = 0,
            counter = 0
        }
        if not skip_item_init then
            for _, item in pairs(recipe[category]) do
                LineItem.add_to_list(line[category], LineItem.init(item, category))
            end
        end
    end

    return line
end

local function get_line(player, subfactory_id, floor_id, id)
    return global.players[player.index].factory.subfactories[subfactory_id].Floor.datasets[floor_id].lines[id]
end


function Line.get_recipe_name(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).recipe_name
end

function Line.set_recipe_category(player, subfactory_id, floor_id, id, recipe_category)
    get_line(player, subfactory_id, floor_id, id).recipe_category = recipe_category
end

function Line.get_recipe_category(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).recipe_category
end


function Line.set_percentage(player, subfactory_id, floor_id, id, percentage)
    get_line(player, subfactory_id, floor_id, id).percentage = percentage
end

function Line.get_percentage(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).percentage
end


function Line.set_machine_name(player, subfactory_id, floor_id, id, machine_name)
    get_line(player, subfactory_id, floor_id, id).machine_name = machine_name
end

function Line.get_machine_name(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).machine_name
end


function Line.set_energy_consumption(player, subfactory_id, floor_id, id, energy_consumption)
    get_line(player, subfactory_id, floor_id, id).energy_consumption = energy_consumption
end

function Line.get_energy_consumption(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).energy_consumption
end


-- Resets all data to stock (unused line), to be updated afterwards
function Line.reset(player, subfactory_id, floor_id, id)
    local self = get_line(player, subfactory_id, floor_id, id)
    self.energy_consumption = 0
    self.machine_count = 0

    for product_id, product in pairs(self.products.datasets) do
        if product.kind == "byproducts" then
            if product.duplicate then LineItem.delete_from_list(self.products, product_id)
            else product.kind = "products"; product.amount = 0 end
        end
    end
    for _, ingredient in pairs(self.ingredients.datasets) do ingredient.amount = 0 end
end


function Line.get_item(player, subfactory_id, floor_id, id, type, item_id)
    local self = get_line(player, subfactory_id, floor_id, id)
    if self.type == "FloorReference" then self = Floor.get_aggregate_line(player, subfactory_id, self.floor_id) end
    return self[type].datasets[item_id]
end

function Line.get_items_in_order(player, subfactory_id, floor_id, id, category)
    local self = get_line(player, subfactory_id, floor_id, id)
    if self.type == "FloorReference" then self = Floor.get_aggregate_line(player, subfactory_id, self.floor_id) end
    return data_util.order_by_position(self[category].datasets)
end


function Line.is_valid(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).valid
end

-- Determines and sets the validity of given Line
function Line.check_validity(player, subfactory_id, floor_id, id)
    local self = get_line(player, subfactory_id, floor_id, id)
    local recipe = global.all_recipes[self.recipe_name]

    self.valid = true
    if recipe == nil then
        self.valid = false
    else
        if recipe.category ~= self.recipe_category then
            self.valid = false
        else
            local machine = global.all_machines[self.recipe_category].machines[self.machine_name]
            if machine == nil then self.valid = false end
        end
    end

    return self.valid
end

-- Attempts to repair missing machines
function Line.attempt_repair(player, subfactory_id, floor_id, id)
    local self = get_line(player, subfactory_id, floor_id, id)
    local recipe = global.all_recipes[self.recipe_name]

    if recipe == nil then
        return false
    else
        if recipe.category ~= self.recipe_category then
            self.recipe_category = recipe.category
            self.machine_name = data_util.get_default_machine(player, recipe.category).name
        else
            local machine = global.all_machines[self.recipe_category].machines[self.machine_name]
            if machine == nil then
                self.machine_name = data_util.get_default_machine(player, recipe.category).name
            end
        end
        self.valid = true
        return self.valid
    end
end


function Line.set_gui_position(player, subfactory_id, floor_id, id, gui_position)
    get_line(player, subfactory_id, floor_id, id).gui_position = gui_position
end

function Line.get_gui_position(player, subfactory_id, floor_id, id)
    return get_line(player, subfactory_id, floor_id, id).gui_position
end
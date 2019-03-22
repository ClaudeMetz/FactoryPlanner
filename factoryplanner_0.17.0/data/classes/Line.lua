-- Represents an (assembly) line, uses a single recipe
Line = {}

function Line.init(player, recipe)
    local recipe_category = recipe.category
    if recipe_category == "basic-solid" and #recipe.ingredients > 1 then recipe_category = "complex-solid" end
    local default_machine = data_util.get_default_machine(player, recipe_category)
    
    local function create_item_table(items)
        local index = 1
        local table = {}
        for _, item in pairs(items) do
            if item.amount == nil then item.amount = item.probability end
            table[index] = {
                name = item.name,
                type = item.type,
                ratio = item.amount,
                amount = 0,
                gui_position = index
            }
            index = index + 1
        end
        return table
    end

    return {
        id = 0,
        recipe_name = recipe.name,
        recipe_category = recipe_category,
        percentage = 100,
        machine_name = default_machine.name,
        machine_count = 0,
        energy_consumption = 0,  -- in Watt
        products = create_item_table(recipe.products),
        byproducts = {},  -- left empty until a refresh moves products over
        ingredients = create_item_table(recipe.ingredients),
        valid = true,
        gui_position = 0,
        type = "Line"
    }
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
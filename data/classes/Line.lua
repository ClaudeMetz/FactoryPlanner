-- Represents an (assembly) line, uses a single recipe
Line = {}

function Line.init(recipe)
    local machine_name = data_util.get_default_machine(recipe.category).name
    return {
        id = 0,
        recipe_name = recipe.name,
        recipe_category = recipe.category,
        percentage = 100,
        machine_name = machine_name,
        energy_consumption = 0,  -- in Watts
        products = recipe.products,
        byproducts = {},
        ingredients = recipe.ingredients,
        valid = true,
        gui_position = 0,
        type = "Line"
    }
end

local function get_line(subfactory_id, floor_id, id)
    return global.factory.subfactories[subfactory_id].Floor.datasets[floor_id].lines[id]
end


function Line.get_recipe_name(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).recipe_name
end

function Line.set_recipe_category(subfactory_id, floor_id, id, recipe_category)
    get_line(subfactory_id, floor_id, id).recipe_category = recipe_category
end

function Line.get_recipe_category(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).recipe_category
end


function Line.set_percentage(subfactory_id, floor_id, id, percentage)
    get_line(subfactory_id, floor_id, id).percentage = percentage
end

function Line.get_percentage(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).percentage
end


function Line.set_machine_name(subfactory_id, floor_id, id, machine_name)
    get_line(subfactory_id, floor_id, id).machine_name = machine_name
end

function Line.get_machine_name(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).machine_name
end


function Line.set_energy_consumption(subfactory_id, floor_id, id, energy_consumption)
    get_line(subfactory_id, floor_id, id).energy_consumption = energy_consumption
end

function Line.get_energy_consumption(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).energy_consumption
end


function Line.is_valid(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).valid
end

-- Determines and sets the validity of given Line
function Line.check_validity(subfactory_id, floor_id, id)
    local self = get_line(subfactory_id, floor_id, id)
    local recipe = global["all_recipes"][self.recipe_name]

    self.valid = true
    if recipe == nil then
        self.valid = false
    else
        if recipe.category ~= self.recipe_category then
            self.valid = false
        else
            local machine = global["all_machines"][self.recipe_category].machines[self.machine_name]
            if machine == nil then
                self.valid = false
            end
        end
    end

    return self.valid
end

-- Attempts to repair missing machines
function Line.attempt_repair(subfactory_id, floor_id, id)
    local self = get_line(subfactory_id, floor_id, id)
    local recipe = global["all_recipes"][self.recipe_name]

    if recipe == nil then
        return false
    else
        if recipe.category ~= self.recipe_category then
            self.recipe_category = recipe.category
            self.machine_name = global["all_machines"][recipe.category].default_machine_name
        else
            local machine = global["all_machines"][self.recipe_category].machines[self.machine_name]
            if machine == nil then
                self.machine_name = global["all_machines"][self.recipe_category].default_machine_name
            end
        end
        self.valid = true
        return self.valid
    end
end


function Line.set_gui_position(subfactory_id, floor_id, id, gui_position)
    get_line(subfactory_id, floor_id, id).gui_position = gui_position
end

function Line.get_gui_position(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).gui_position
end
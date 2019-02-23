-- Represents an (assembly) line, uses a single recipe
Line = {}

function Line.init(recipe, product)
    return {
        recipe_name = recipe.name,
        product_name = product.name,
        product_type = product.item_type,
        percentage = 100,
        valid = true,
        gui_position = 0,
        type = "Line"
    }
end

local function get_line(subfactory_id, floor_id, id)
    return global.factory.subfactories[subfactory_id].Floor.datasets[floor_id].lines[id]
end


function Line.set_recipe_name(subfactory_id, floor_id, id, name)
    get_line(subfactory_id, floor_id, id).name = name
end

function Line.get_recipe_name(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).name
end


function Line.set_percentage(subfactory_id, floor_id, id, percentage)
    get_line(subfactory_id, floor_id, id).percentagee = percentage
end

function Line.get_percentage(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).percentage
end


function Line.is_valid(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).valid
end

-- Determines and sets the validity of given Line
function Line.check_validity(subfactory_id, floor_id, id)
    local self = get_line(subfactory_id, floor_id, id)
    self.valid = (global["all_recipes"][self.recipe_name] ~= nil)
    return self.valid
end


function Line.set_gui_position(subfactory_id, floor_id, id, gui_position)
    get_line(subfactory_id, floor_id, id).gui_position = gui_position
end

function Line.get_gui_position(subfactory_id, floor_id, id)
    return get_line(subfactory_id, floor_id, id).gui_position
end
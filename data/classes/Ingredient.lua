Ingredient = {}

function Ingredient.init(item, amount_required)
    return {
        id = 0,
        name = item.name,
        item_type = item.type,
        amount_required = amount_required,
        valid = true,
        gui_position = 0,
        type = "Ingredient"
    }
end

local function get_ingredient(subfactory_id, id)
    return global.factory.subfactories[subfactory_id].Ingredient.datasets[id]
end


function Ingredient.set_item(subfactory_id, item)
    local self = get_ingredient(subfactory_id, item)
    self.name = item.name
    self.item_type = item.type
end

function Ingredient.get_name(subfactory_id)
    return get_ingredient(subfactory_id, id).name
end

function Ingredient.get_item_type(subfactory_id)
    return get_ingredient(subfactory_id, id).item_type
end


function Ingredient.set_amount_required(subfactory_id, id, amount)
    get_ingredient(subfactory_id, id).amount_required = amount
end

function Ingredient.get_amount_required(subfactory_id, id)
    return get_ingredient(subfactory_id, id).amount_required
end


function Ingredient.is_valid(subfactory_id, id)
    return get_ingredient(subfactory_id, id).valid
end

-- Determines and sets the validity of given Ingredient
function Ingredient.check_validity(subfactory_id, id)
    local self = get_ingredient(subfactory_id, id)
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end


function Ingredient.set_gui_position(subfactory_id, id, gui_position)
    get_ingredient(subfactory_id, id).gui_position = gui_position
end

function Ingredient.get_gui_position(subfactory_id, id)
    return get_ingredient(subfactory_id, id).gui_position
end
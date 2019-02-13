Byproduct = {}

function Byproduct.init(item)
    return {
        name = item.name,
        item_type = item.type,
        amount_produced = 0,
        valid = true,
        gui_position = nil,
        type = "Byproduct"
    }
end

local function get_byproduct(subfactory_id, id)
    return global.factory.subfactories[subfactory_id].Byproduct.datasets[id]
end


function Byproduct.set_name(subfactory_id, name)
    get_byproduct(subfactory_id, id).name = name
end

function Byproduct.get_name(subfactory_id)
    return get_byproduct(subfactory_id, id).name
end


function Byproduct.set_item_type(subfactory_id, item_type)
    get_byproduct(subfactory_id, id).item_type = item_type
end

function Byproduct.get_item_type(subfactory_id)
    return get_byproduct(subfactory_id, id).item_type
end


-- Negative amounts subtract
function Byproduct.add_to_amount_produced(subfactory_id, id, amount)
    local byproduct = get_byproduct(subfactory_id, id)
    byproduct.amount_produced = byproduct.amount_produced + amount
end

function Byproduct.get_amount_produced(subfactory_id, id)
    return get_byproduct(subfactory_id, id).amount_produced
end


function Byproduct.is_valid(subfactory_id, id)
    return get_byproduct(subfactory_id, id).valid
end

-- Determines and sets the validity of given Byproduct
function Byproduct.check_validity(subfactory_id, id)
    local self = get_byproduct(subfactory_id, id)
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end


function Byproduct.set_gui_position(subfactory_id, id, gui_position)
    get_byproduct(subfactory_id, id).gui_position = gui_position
end

function Byproduct.get_gui_position(subfactory_id, id)
    return get_byproduct(subfactory_id, id).gui_position
end
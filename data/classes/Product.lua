Product = {}

function Product.init(item, amount_required)
    return {
        id = 0,
        name = item.name,
        item_type = item.type,
        amount_required = amount_required,
        amount_produced = 0,
        valid = true,
        gui_position = 0,
        type = "Product"
    }
end

local function get_product(player, subfactory_id, id)
    return global.players[player.index].factory.subfactories[subfactory_id].Product.datasets[id]
end


function Product.set_item(player, subfactory_id, id, item)
    local self = get_product(player, subfactory_id, id)
    self.name = item.name
    self.item_type = item.type
end

function Product.get_name(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).name
end

function Product.get_item_type(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).item_type
end


function Product.set_amount_required(player, subfactory_id, id, amount)
    get_product(player, subfactory_id, id).amount_required = amount
end

function Product.get_amount_required(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).amount_required
end


-- Negative amounts subtract
function Product.add_to_amount_produced(player, subfactory_id, id, amount)
    local product = get_product(player, subfactory_id, id)
    product.amount_produced = product.amount_produced + amount
end

function Product.get_amount_produced(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).amount_produced
end


function Product.is_valid(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).valid
end

-- Determines and sets the validity of given Product
function Product.check_validity(player, subfactory_id, id)
    local self = get_product(player, subfactory_id, id)
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end


function Product.set_gui_position(player, subfactory_id, id, gui_position)
    get_product(player, subfactory_id, id).gui_position = gui_position
end

function Product.get_gui_position(player, subfactory_id, id)
    return get_product(player, subfactory_id, id).gui_position
end
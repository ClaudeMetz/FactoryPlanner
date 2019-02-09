Product = {}
Product.__index = Product


function Product:_init(name, amount_required)
    BaseClass._init(self, name)
    self.amount_required = amount_required
    self.amount_produced = 0
end


function Product:set_amount_required(amount)
    self.amount_required = amount
end

function Product:get_amount_required()
    return self.amount_required
end


-- Negative amounts subtract
function Product:add_to_amount_produced(amount)
    self.amount_produced = self.amount_produced + amount
end

function Product:get_amount_produced()
    return self.amount_produced
end
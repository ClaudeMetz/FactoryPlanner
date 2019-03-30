-- 'Class' representing an item in the general sense
Item = {}

function Item.init(base_item, class)
    return {
        name = base_item.name,
        type = base_item.type,
        amount = 0,  -- produced amount
        required_amount = 0,
        valid = true,
        class = class
    }
end

function Item.update_validity(self)
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end
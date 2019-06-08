-- 'Class' representing an item in the general sense
Item = {}

-- If no item type is passed, the type of the base item is assumed
function Item.init(base_item, item_type, class, amount)
    local item = {
        name = base_item.name,
        type = nil,
        amount = amount or 0,  -- produced amount
        required_amount = 0,
        valid = true,
        class = class
    }
    
    if item_type then item.type = item_type
    else item.type = base_item.type end

    return item
end

function Item.update_validity(self)
    -- Check entity ores in assembly lines correctly
    local type = (self.type == "entity") and "item" or self.type

    self.valid = (global.all_items[type][self.name] ~= nil)
    return self.valid
end
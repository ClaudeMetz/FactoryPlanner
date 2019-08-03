-- 'Class' representing a top level item, for reasons that will become clearer in the future
TopLevelItem = {}

-- Initialised by passing a prototype from the all_items global table
function TopLevelItem.init_by_proto(proto, class, amount, required_amount)
    local item = Item.init_by_proto(proto, class, amount)
    item.required_amount = required_amount or 0
    item.top_level = true
    return item
end

-- Initialised by passing a basic item table {name, type, amount}
function TopLevelItem.init_by_item(item, class, amount, required_amount)
    local type = global.all_items.types[global.all_items.map[item.type]]
    local proto = type.items[type.map[item.name]]
    return TopLevelItem.init_by_proto(proto, class, amount, required_amount)
end

-- All other Item methods are valid/identical for this class atm
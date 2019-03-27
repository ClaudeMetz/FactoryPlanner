-- This is not really a class in the same sense as the others in this project,
-- but it serves to unify some common operations in a class-like fashion
-- (The whole class system is a mess and needs to be redone at some point)

LineItem = {}

-- Can be created using a Factorio item or a LineItem
function LineItem.init(item, kind)
    if item.amount == nil then item.amount = item.probability end

    return {
        id = 0,
        name = item.name,
        item_type = item.type or item.item_type,
        ratio = item.amount,
        amount = 0,
        valid = true,
        gui_position = 0,
        kind = kind,
        duplicate = false,
        type = "LineItem"
    }
end


-- Adds given LineItem to the end of the list
function LineItem.add_to_list(list, line_item)
    list.index = list.index + 1
    list.counter = list.counter + 1
    line_item.id = list.index
    line_item.gui_position = list.counter
    list.datasets[list.index] = line_item
    return list.index
end

-- Deletes line item indicated by the id from the list
function LineItem.delete_from_list(list, item_id)
    list.counter = list.counter - 1
    data_util.update_positions(list.datasets, list.datasets[item_id].gui_position)
    list.datasets[item_id] = nil
end
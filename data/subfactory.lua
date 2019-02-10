Subfactory = {}

function Subfactory.init(name, icon)
    local subfactory = {
        name = name,
        icon = icon,
        timescale = 60,
        notes = "",
        valid = true,
        gui_position = nil,
        type = "Subfactory"
    }

    for _, data_type in ipairs(data_types) do
        subfactory[data_type] = {
            datasets = {},
            index = 0,
            counter = 0
        }
    end
    
    return subfactory
end

local data_types = {"Ingredient", "Product", "Byproduct"}
local function get_subfactory(id)
    return global.factory.subfactories[id]
end


function Subfactory.set_name(id, name)
    get_subfactory(id).name = name
end

function Subfactory.get_name(id)
    return get_subfactory(id).name
end


function Subfactory.set_icon(id, icon)
    get_subfactory(id).icon = icon
end

function Subfactory.get_icon(id)
    return get_subfactory(id).icon
end


function Subfactory.set_timescale(id, timescale)
    get_subfactory(id).timescale = timescale
end

function Subfactory.get_timescale(id)
    return get_subfactory(id).timescale
end


function Subfactory.set_notes(id, notes)
    get_subfactory(id).notes = notes
end

function Subfactory.get_notes(id)
    return get_subfactory(id).notes
end


function Subfactory.add(id, dataset)
    local data_table = get_subfactory(id)[dataset.type]
    data_table.index = data_table.index + 1
    data_table.counter = data_table.counter + 1
    dataset.gui_position = data_table.counter
    data_table.datasets[data_table.index] = dataset
    return data_table.index
end

function Subfactory.delete(id, type, dataset_id)
    local data_table = get_subfactory(id)[type]
    data_table.counter = data_table.counter - 1
    update_positions(data_table.datasets, data_table.datasets[dataset_id].gui_position)
    data_table.datasets[dataset_id] = nil
end


function Subfactory.get_count(id, type)
    return get_subfactory(id)[type].counter
end

function Subfactory.get(id, type, dataset_id)
    return get_subfactory(id)[type].datasets[dataset_id]
end

-- Returns dataset id's in order by position (-> [gui_position] = id)
function Subfactory.get_in_order(id, type)
    return order_by_position(get_subfactory(id)[type].datasets)
end


-- Returns true when a product already exists in given subfactory
function Subfactory.product_exists(id, product_name)
    for _, product in pairs(get_subfactory(id).Product.datasets) do
        if product.name == product_name then return true end
    end
    return false
end


function Subfactory.is_valid(id)
    return get_subfactory(id).valid
end

-- Updates validity values of the datasets of all data_types
function Subfactory.update_validity(id)
    local subfactory = get_subfactory(id)
    for _, data_type in ipairs(data_types) do
        for dataset_id, _ in pairs(subfactory[data_type].datasets) do
            if not _G[data_type].check_validity(id, dataset_id) then
                subfactory.valid = false
                return
            end
        end
    end
    get_subfactory(id).valid = true
end

-- Removes all invalid datasets from the given subfactory
function Subfactory.remove_invalid_datasets(id)
    local subfactory = get_subfactory(id)
    for _, data_type in ipairs(data_types) do
        for dataset_id, dataset in pairs(subfactory[data_type].datasets) do
            if not dataset.valid then
                Subfactory.delete(id, data_type, dataset_id)
            end
        end
    end
    get_subfactory(id).valid = true
end


function Subfactory.set_gui_position(id, gui_position)
    get_subfactory(id).gui_position = gui_position
end

function Subfactory.get_gui_position(id)
    return get_subfactory(id).gui_position
end

function Subfactory.shift(id, type, dataset_id, direction)
    local data_table = get_subfactory(id)[type]
    shift_position(data_table.datasets, dataset_id, direction, data_table.counter)
end
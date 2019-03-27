Subfactory = {}

local data_types = {"Ingredient", "Product", "Byproduct", "Floor"}

function Subfactory.init(name, icon)
    if icon ~= nil and icon.type == "virtual" then icon.type = "virtual-signal" end
    local subfactory = {
        id = 0,
        name = name,
        icon = icon,
        timescale = 60,  -- in seconds
        energy_consumption = 0,  -- in Watts
        notes = "",
        selected_floor_id = 0,
        valid = true,
        gui_position = 0,
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


local function get_subfactory(player, id)
    return global.players[player.index].factory.subfactories[id]
end


function Subfactory.set_name(player, id, name)
    get_subfactory(player, id).name = name
end

function Subfactory.get_name(player, id)
    return get_subfactory(player, id).name
end


function Subfactory.set_icon(player, id, icon)
    if icon ~= nil and icon.type == "virtual" then icon.type = "virtual-signal" end
    get_subfactory(player, id).icon = icon
end

function Subfactory.get_icon(player, id)
    return get_subfactory(player, id).icon
end


function Subfactory.set_timescale(player, id, timescale)
    get_subfactory(player, id).timescale = timescale
end

function Subfactory.get_timescale(player, id)
    return get_subfactory(player, id).timescale
end


function Subfactory.set_energy_consumption(player, id, energy_consumption)
    get_subfactory(player, id).energy_consumption = energy_consumption
end

function Subfactory.get_energy_consumption(player, id)
    return get_subfactory(player, id).energy_consumption
end


function Subfactory.set_notes(player, id, notes)
    get_subfactory(player, id).notes = notes
end

function Subfactory.get_notes(player, id)
    return get_subfactory(player, id).notes
end


function Subfactory.set_selected_floor_id(player, id, floor_id)
    get_subfactory(player, id).selected_floor_id = floor_id
end

function Subfactory.get_selected_floor_id(player, id)
    return get_subfactory(player, id).selected_floor_id
end

function Subfactory.change_selected_floor(player, id, step)
    local selected_floor = Subfactory.get(player, id, "Floor", Subfactory.get_selected_floor_id(player, id))
    if step == "up" then
        get_subfactory(player, id).selected_floor_id = selected_floor.parent_id
    elseif step == "top" then
        get_subfactory(player, id).selected_floor_id = 1
    end
    -- Remove floor if no recipes have been added to it
    if selected_floor.level > 1 and selected_floor.line_counter == 1 then
        Floor.convert_floor_to_line(player, id, selected_floor.id)
    end
end


-- Updates the subfactories top level data after it was recalculated
function Subfactory.update_top_level_data(player, id)
    local self = get_subfactory(player, id)
    local aggregate = Floor.get_aggregate(player, id, 1)

    self.energy_consumption = aggregate.energy_consumption

    -- For products, only the amount_produced can change automatically, no addition/removal possible
    for _, product in pairs(self["Product"].datasets) do
        local aggregate_product = aggregate.products[product.name]
        if not aggregate_product then  -- Product amount produced exactly
            product.amount_produced = product.amount_required
        else
            if product.amount_produced > 0 then  -- Product underproduced
                local amount = product.amount_produced + aggregate_product.amount
                Aggregate.add_item(aggregate, "ingredients", aggregate_product, amount, false)
                product.amount_produced = 0
            else  -- Product overproduced
                product.amount_produced = product.amount_required + aggregate_product.amount
            end
        end
    end

    -- For byproducts and ingredients, existence(add/remove) and amount can change, position needs to be preserved
    local function update_top_level_category(type, aggregate_items, top_level_items)
        -- Add to or create relevant top level items
        local touched_items = {}
        for name, item in pairs(aggregate_items) do
            local top_level_item = Subfactory.find_by_name(player, id, type, name)
            if top_level_item == nil then
                local new_top_level_item = _G[type].init(item, item.amount)
                Subfactory.add(player, id, new_top_level_item)
            else
                if type == "Byproduct" then
                    top_level_item.amount_produced = item.amount
                elseif type == "Ingredient" then
                    top_level_item.amount_required = item.amount
                end
            end
            touched_items[name] = true
        end

        -- Remove top level items that are not present anymore
        for item_id, item in pairs(top_level_items) do
            if not touched_items[item.name] then
                Subfactory.delete(player, id, type, item_id)
            end
        end
    end

    update_top_level_category("Byproduct", aggregate.byproducts, self["Byproduct"].datasets)
    update_top_level_category("Ingredient", aggregate.ingredients, self["Ingredient"].datasets)
end


function Subfactory.add(player, id, dataset)
    local self = get_subfactory(player, id)
    local data_table = self[dataset.type]

    data_table.index = data_table.index + 1
    data_table.counter = data_table.counter + 1

    dataset.id = data_table.index
    if dataset.type == "Floor" then
        if self.selected_floor_id == 0 then  -- First floor of the subfactory
            dataset.level = 1
            dataset.parent_id = 0
        end
        self.selected_floor_id = data_table.index
    else dataset.gui_position = data_table.counter end

    data_table.datasets[data_table.index] = dataset
    return data_table.index
end

function Subfactory.delete(player, id, type, dataset_id)
    local data_table = get_subfactory(player, id)[type]
    data_table.counter = data_table.counter - 1
    if type == "Floor" then
        Floor.delete_subfloors(player, id, dataset_id)
    else
        data_util.update_positions(data_table.datasets, data_table.datasets[dataset_id].gui_position)
    end
    data_table.datasets[dataset_id] = nil
end


function Subfactory.get_count(player, id, type)
    return get_subfactory(player, id)[type].counter
end

function Subfactory.get(player, id, type, dataset_id)
    return get_subfactory(player, id)[type].datasets[dataset_id]
end

-- Returns dataset id's in order by position (-> [gui_position] = id)
function Subfactory.get_in_order(player, id, type)
    return data_util.order_by_position(get_subfactory(player, id)[type].datasets)
end


-- Returns true when a product already exists in the given subfactory
function Subfactory.product_exists(player, id, product)
    if product ~= nil then
        for _, p in pairs(get_subfactory(player, id).Product.datasets) do
            if p.name == product.name then return true end
        end
    end
    return false
end

-- Finds items of given type by their name, returns nil if not found
function Subfactory.find_by_name(player, id, type, name)
    for _, item in pairs(get_subfactory(player, id)[type].datasets) do
        if item.name == name then return item end
    end
    return nil
end

function Subfactory.is_valid(player, id)
    return get_subfactory(player, id).valid
end

-- Updates validity values of the datasets of all data_types
-- Floors can be checked in any order and separately without problem
function Subfactory.check_validity(player, id)
    local self = get_subfactory(player, id)
    self.valid = true
    for _, data_type in ipairs(data_types) do
        for dataset_id, _ in pairs(self[data_type].datasets) do
            if not _G[data_type].check_validity(player, id, dataset_id) then
                self.valid = false
            end
        end
    end
end

-- Removes all invalid datasets from the given subfactory
function Subfactory.remove_invalid_datasets(player, id)
    local self = get_subfactory(player, id)
    for _, data_type in ipairs(data_types) do
        for dataset_id, dataset in pairs(self[data_type].datasets) do
            if data_type ~= "Floor" and not dataset.valid then
                Subfactory.delete(player, id, data_type, dataset_id)
            end
        end
    end
    -- Only called on the topmost dataset, which recursively goes through it's subordinates
    Floor.remove_invalid_datasets(player, id, 1)

    self.valid = true
end


function Subfactory.set_gui_position(player, id, gui_position)
    get_subfactory(player, id).gui_position = gui_position
end

function Subfactory.get_gui_position(player, id)
    return get_subfactory(player, id).gui_position
end

function Subfactory.shift(player, id, type, dataset_id, direction)
    local data_table = get_subfactory(player, id)[type]
    data_util.shift_position(data_table.datasets, dataset_id, direction, data_table.counter)
end
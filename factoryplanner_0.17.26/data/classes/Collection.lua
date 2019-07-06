-- 'Class' representing a list of objects/datasets with some useful methods
-- (An object only becomes a dataset once it is added to the collection)
Collection = {}

function Collection.init()
    return {
        datasets = {},
        index = 0,
        count = 0,
        type = "Collection"
    }
end

function Collection.add(self, object)
    self.index = self.index + 1
    self.count = self.count + 1
    object.id = self.index
    object.gui_position = self.count
    self.datasets[self.index] = object
    return object  -- Returning it here feels nice
end

function Collection.remove(self, dataset)
    -- Move positions of datasets after the deleted one down by one
    for _, d in pairs(self.datasets) do
        if d.gui_position > dataset.gui_position then
            d.gui_position = d.gui_position - 1
        end
    end

    self.count = self.count - 1
    self.datasets[dataset.id] = nil
end

-- Replaces the dataset with the new object in-place
function Collection.replace(self, dataset, object)
    object.parent = dataset.parent
    object.id = dataset.id
    object.gui_position = dataset.gui_position
    self.datasets[dataset.id] = object
    return object  -- Returning it here feels nice
end

function Collection.get(self, object_id)
    return self.datasets[object_id]
end

-- Return format: {[gui_position] = dataset}
function Collection.get_in_order(self, reverse)
    local ordered_datasets = {}
    for _, dataset in pairs(self.datasets) do
        local table_position = (reverse) and (self.count - dataset.gui_position + 1) or dataset.gui_position
        ordered_datasets[table_position] = dataset
    end
    return ordered_datasets
end

-- Returns the dataset specified by the gui_position
function Collection.get_by_gui_position(self, gui_position)
    if gui_position == 0 then return nil end
    for _, dataset in pairs(self.datasets) do
        if dataset.gui_position == gui_position then
            return dataset
        end
    end
end

-- Returns the dataset with the given name, nil if it doesn't exist
function Collection.get_by_name(self, name)
    for _, dataset in pairs(self.datasets) do
        -- Check agains the prototype name, if a prototype exists
        if dataset.proto ~= nil and dataset.proto.name == name then
            return dataset
        elseif dataset.name == name then
            return dataset
        end
    end
    return nil
end

-- Shifts given dataset in given direction
function Collection.shift(self, main_dataset, direction)
    local main_gui_position = main_dataset.gui_position

    -- Doesn't shift if outmost elements are being shifted further outward
    if (main_gui_position == 1 and direction == "negative") or
      (main_gui_position == self.count and direction == "positive") then 
        return 
    end

    local secondary_gui_position
    if direction == "positive" then
        secondary_gui_position = main_gui_position + 1
    else  -- direction == "negative"
        secondary_gui_position = main_gui_position - 1
    end
    local secondary_dataset = Collection.get_by_gui_position(self, secondary_gui_position)

    main_dataset.gui_position = secondary_gui_position
    secondary_dataset.gui_position = main_gui_position
end

-- Updates the validity of all datasets in this Collection
function Collection.update_validity(self, class)
    local valid = true
    for _, dataset in pairs(self.datasets) do
        if not _G[class].update_validity(dataset) then
            valid = false
        end
    end
    return valid
end

-- Removes any invalid, unrepairable datasets from the Collection
function Collection.repair_invalid_datasets(self, player, class, parent)
    for _, dataset in pairs(self.datasets) do
        if not dataset.valid and not _G[class].attempt_repair(dataset, player) then
            _G[parent.class].remove(parent, dataset)
        end
    end
end
-- 'Class' representing a list of objects/datasets with some useful methods
-- (An object only becomes a dataset once it is added to the collection)
Collection = {}

function Collection.init()
    return {
        datasets = {},
        index = 0,
        count = 0,
        class = "Collection"
    }
end


-- Adds given object to the end of the collection
function Collection.add(self, object)
    if not object then error("Can't insert nil dataset") end

    self.index = self.index + 1
    object.id = self.index
    self.datasets[self.index] = object

    self.count = self.count + 1
    object.gui_position = self.count

    return object  -- Returning it here feels nice
end

-- Inserts the given object at the given position, shifting other elements down
function Collection.insert_at(self, gui_position, object)
    if not object then error("Can't insert nil dataset")
    elseif not gui_position then error("Can't insert at nil position") end

    self.index = self.index + 1
    object.id = self.index

    self.count = self.count + 1
    object.gui_position = gui_position

    for _, dataset in pairs(self.datasets) do
        if dataset.gui_position >= gui_position then
            dataset.gui_position = dataset.gui_position + 1
        end
    end

    self.datasets[self.index] = object
    return object
end

function Collection.remove(self, dataset)
    if not dataset then error("Can't remove nil dataset") end

    -- Move positions of datasets after the deleted one down by one
    for _, d in pairs(self.datasets) do
        if d.gui_position > dataset.gui_position then
            d.gui_position = d.gui_position - 1
        end
    end

    self.count = self.count - 1
    self.datasets[dataset.id] = nil

    -- Returning the deleted position here to allow for GUI adjustments
    return dataset.gui_position
end

-- Replaces the dataset with the new object in-place
function Collection.replace(self, dataset, object)
    if not dataset then error("Can't replace nil dataset")
    elseif not object then error("Can't replace with nil object") end

    object.id = dataset.id
    object.gui_position = dataset.gui_position
    self.datasets[dataset.id] = object
    return object  -- Returning it here feels nice
end


function Collection.get(self, object_id)
    return self.datasets[object_id]
end

-- For when order doesn't matter
function Collection.get_all(self)
    return self.datasets
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
        -- Check against the prototype, if it exists
        local check_against = dataset.proto or dataset
        if check_against.name == name then
            return dataset
        end
    end
    return nil
end

-- Returns the dataset with the given type and name, nil if it doesn't exist
function Collection.get_by_type_and_name(self, type_name, name)
    for _, dataset in pairs(self.datasets) do
        -- Check against the prototype, if it exists
        local check_against = dataset.proto or dataset
        if check_against.type == type_name and check_against.name == name then
            return dataset
        end
    end
    return nil
end


-- Shifts given dataset in given direction
function Collection.shift(self, main_dataset, direction, bottom_position)
    if not main_dataset then error("Can't shift nil dataset")
    elseif not(direction == "negative" or direction == "positive") then error("Can't shift in invalid direction") end

    local main_gui_position = main_dataset.gui_position

    -- Doesn't shift if outmost elements are being shifted further outward
    if (main_gui_position == bottom_position and direction == "negative") or
      (main_gui_position == self.count and direction == "positive") then
        return false
    end

    local secondary_gui_position = (direction == "positive") and (main_gui_position + 1) or (main_gui_position - 1)
    local secondary_dataset = Collection.get_by_gui_position(self, secondary_gui_position)
    main_dataset.gui_position = secondary_gui_position
    secondary_dataset.gui_position = main_gui_position

    return true
end

-- Shifts the given dataset to the end of the collection in the given direction
function Collection.shift_to_end(self, main_dataset, direction, bottom_position)
    if not main_dataset then error("Can't shift nil dataset")
    elseif not(direction == "negative" or direction == "positive") then error("Can't shift in invalid direction") end

    local main_gui_position = main_dataset.gui_position

    -- Doesn't shift if outmost elements are being shifted further outward
    if (main_gui_position == bottom_position and direction == "negative") or
      (main_gui_position == self.count and direction == "positive") then
        return false
    end

    local secondary_gui_position = (direction == "positive") and self.count or bottom_position
    -- To simplify the code, remove the dataset and re-insert it at the right position
    Collection.remove(self, main_dataset)
    Collection.insert_at(self, secondary_gui_position, main_dataset)

    return true
end


-- Packs every dataset in this collection
function Collection.pack(self, object_class)
    local packed_collection = {
        objects = {},
        class = self.class
    }

    for _, dataset in ipairs(Collection.get_in_order(self)) do
        table.insert(packed_collection.objects, object_class.pack(dataset))
    end

    return packed_collection
end

-- Unpacks every dataset in this collection
function Collection.unpack(packed_self, parent, object_class)
    local self = Collection.init()
    self.class = packed_self.class

    for _, object in ipairs(packed_self.objects) do  -- packed objects already in array order
        local dataset = Collection.add(self, object_class.unpack(object))
        dataset.parent = parent
    end

    return self
end


-- Updates the validity of all datasets in this collection
function Collection.validate_datasets(self, object_class)
    local valid = true

    for _, dataset in pairs(self.datasets) do
        -- Stays true until a single dataset is invalid, then stays false
        valid = object_class.validate(dataset) and valid
    end

    return valid
end

-- Removes any invalid, unrepairable datasets from the collection
function Collection.repair_datasets(self, player, object_class)
    for _, dataset in pairs(self.datasets) do
        if not dataset.valid and not object_class.repair(dataset, player) then
            _G[dataset.parent.class].remove(dataset.parent, dataset)
        end
    end
end

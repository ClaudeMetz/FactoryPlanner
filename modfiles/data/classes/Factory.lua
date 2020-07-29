-- 'Class' representing the whole of a players actual data, including all subfactories
Factory = {}

function Factory.init()
    return {
        Subfactory = Collection.init("Subfactory"),
        selected_subfactory = nil,
        -- A Factory can not become invalid
        class = "Factory"
    }
end

function Factory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Factory.remove(self, dataset)
    return Collection.remove(self[dataset.class], dataset)
end

function Factory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Factory.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Factory.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Factory.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
end

function Factory.shift_to_end(self, dataset, direction)
    return Collection.shift_to_end(self[dataset.class], dataset, direction)
end

-- Imports every subfactory in the given string to this Factory, returning a reference to the first one
function Factory.import_by_string(self, player, export_string)
    local import_factory = data_util.porter.get_subfactories(player, export_string)
    -- No error handling here, as the export_string for this will always be known to work

    local first_subfactory = nil
    for _, subfactory in pairs(Factory.get_in_order(import_factory, "Subfactory")) do
        Factory.add(self, subfactory)
        first_subfactory = first_subfactory or subfactory
    end

    return first_subfactory
end


-- Updates every top level product of this Factory to the given product definition type
function Factory.update_product_definitions(self, new_defined_by)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        Subfactory.update_product_definitions(subfactory, new_defined_by)
    end
end

-- Updates the ingredient satisfaction data on every subfactory
function Factory.update_ingredient_satisfactions(self)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        calculation.determine_ingredient_satisfaction(subfactory)
    end
end
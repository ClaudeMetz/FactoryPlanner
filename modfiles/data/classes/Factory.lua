-- 'Class' representing the whole of a players actual data, including all subfactories
Factory = {}

function Factory.init()
    return {
        Subfactory = Collection.init(),
        selected_subfactory = nil,
        valid = true,
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


-- Updates every top level product of this Factory to the given product definition type
function Factory.update_product_definitions(self, new_defined_by)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        Subfactory.update_product_definitions(subfactory, new_defined_by)
    end
end


-- Updates the validity of the factory from top to bottom
function Factory.update_validity(self)
    local classes = {Subfactory = "Subfactory"}
    self.valid = run_validation_updates(self, classes)
end
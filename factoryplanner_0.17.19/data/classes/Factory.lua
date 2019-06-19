-- 'Class' representing the whole of a players actual data, including all subfactories
Factory = {}

function Factory.init()
    return {
        Subfactory = Collection.init(),
        valid = true,
        class = "Factory"
    }
end

function Factory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Factory.remove(self, dataset)
    Collection.remove(self[dataset.class], dataset)
end

function Factory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Factory.get_in_order(self, class)
    return Collection.get_in_order(self[class])
end

function Factory.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Factory.shift(self, dataset, direction)
    Collection.shift(self[dataset.class], dataset, direction)
end

-- Updates the validity of the factory from top to bottom
function Factory.update_validity(self, player)
    local classes = {Subfactory = "Subfactory"}
    self.valid = data_util.run_validation_updates(player, self, classes)
end
Factory = {}

function Factory.init()
    return {
        subfactories = {},
        subfactory_index = 0,
        subfactory_count = 0
    }
end


function Factory.add_subfactory(subfactory)
    local self = global.factory
    self.subfactory_index = self.subfactory_index + 1
    self.subfactory_count = self.subfactory_count + 1
    subfactory.gui_position = self.subfactory_count
    self.subfactories[self.subfactory_index] = subfactory
    return self.subfactory_index
end

function Factory.delete_subfactory(subfactory_id)
    local self = global.factory
    self.subfactory_count = self.subfactory_count - 1
    data_util.update_positions(self.subfactories, Subfactory.get_gui_position(subfactory_id))
    self.subfactories[subfactory_id] = nil
end


function Factory.get_subfactory_count()
    return global.factory.subfactory_count
end

function Factory.get_subfactory(subfactory_id)
    return global.factory.subfactories[subfactory_id]
end

-- For convenience
function Factory.get_selected_subfactory()
    return global.factory.subfactories[global["selected_subfactory_id"]]
end

-- Returns subfactory id's in order by position (-> [gui_position] = id)
function Factory.get_subfactories_in_order()
    return data_util.order_by_position(global.factory.subfactories)
end

-- Used for changing the selected subfactory on deletion
function Factory.get_subfactory_id_by_position(gui_position)
    return data_util.get_id_by_position(global.factory.subfactories, gui_position)
end


-- Updates the validity values of all subfactories
function Factory.update_validity()
    for subfactory_id, _ in pairs(global.factory.subfactories) do
        Subfactory.update_validity(subfactory_id)
    end
end


function Factory.shift_subfactory(subfactory_id, direction)
    local self = global.factory
    data_util.shift_position(self.subfactories, subfactory_id, direction, self.subfactory_count)
end
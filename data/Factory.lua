Factory = {}
Factory.__index = Factory


function Factory:_init()
    self.subfactories = {}
    self.subfactory_index = 0
    self.subfactory_count = 0
end


function Factory:add_subfactory(subfactory)
    self.subfactory_index = self.subfactory_index + 1
    self.subfactory_count = self.subfactory_count + 1
    subfactory:set_gui_position(self.subfactory_count)
    self.subfactories[self.subfactory_index] = subfactory
    return self.subfactory_index
end

function Factory:delete_subfactory(subfactory_id)
    self.subfactory_count = self.subfactory_count - 1
    update_positions(self.subfactories, self.subfactories[subfactory_id]:get_gui_position())
    self.subfactories[subfactory_id] = nil
end


function Factory:get_subfactory_count()
    return self.subfactory_count
end

function Factory:get_subfactory(subfactory_id)
    return self.subfactories[subfactory_id]
end

-- For convenience
function Factory:get_selected_subfactory()
    return self.subfactories[global["selected_subfactory_id"]]
end

function Factory:get_subfactories_in_order()
    return order_by_position(self.subfactories)
end


-- Used for changing the selected subfactory on deletion
function Factory:get_subfactory_id_by_position(gui_position)
    return get_id_by_position(self.subfactories, gui_position)
end

function Factory:update_validity()
    for _, subfactory in self.subfactories do
        subfactory:update_validity()
    end
end


function Factory:shift_subfactory(subfactory_id, direction)
    shift_position(self.subfactories, subfactory_id, direction, self.subfactory_count)
end
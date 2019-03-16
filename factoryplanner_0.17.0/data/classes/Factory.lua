Factory = {}

function Factory.init()
    return {
        subfactories = {},
        subfactory_index = 0,
        subfactory_counter = 0
    }
end


local function get_factory(player)
    return global.players[player.index].factory
end


function Factory.add_subfactory(player, subfactory)
    local self = get_factory(player)
    self.subfactory_index = self.subfactory_index + 1
    self.subfactory_counter = self.subfactory_counter + 1
    subfactory.id = self.subfactory_index
    subfactory.gui_position = self.subfactory_counter
    self.subfactories[self.subfactory_index] = subfactory
    Subfactory.add(player, self.subfactory_index, Floor.init())  -- add first floor of the subfactory
    return self.subfactory_index
end

function Factory.delete_subfactory(player, subfactory_id)
    local self = get_factory(player)
    self.subfactory_counter = self.subfactory_counter - 1
    data_util.update_positions(self.subfactories, self.subfactories[subfactory_id].gui_position)
    self.subfactories[subfactory_id] = nil
end


function Factory.get_subfactory_count(player)
    return global.players[player.index].factory.subfactory_counter
end

function Factory.get_subfactory(player, subfactory_id)
    return global.players[player.index].factory.subfactories[subfactory_id]
end

-- For convenience
function Factory.get_selected_subfactory(player)
    local player_table = global.players[player.index]
    return player_table.factory.subfactories[player_table.selected_subfactory_id]
end

-- Returns subfactory id's in order by position (-> [gui_position] = id)
function Factory.get_subfactories_in_order(player)
    return data_util.order_by_position(global.players[player.index].factory.subfactories)
end

-- Used for changing the selected subfactory on deletion
function Factory.get_subfactory_id_by_position(player, gui_position)
    return data_util.get_id_by_position(global.players[player.index].factory.subfactories, gui_position)
end


-- Updates the validity values of all subfactories
function Factory.update_validity(player)
    for subfactory_id, _ in pairs(global.players[player.index].factory.subfactories) do
        Subfactory.check_validity(player, subfactory_id)
    end
end


function Factory.shift_subfactory(player, subfactory_id, direction)
    local self = get_factory(player)
    data_util.shift_position(self.subfactories, subfactory_id, direction, self.subfactory_counter)
end
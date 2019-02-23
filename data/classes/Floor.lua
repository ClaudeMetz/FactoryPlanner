-- Represents a level of a subfactory, is a container for (assembly) lines
Floor = {}

function Floor.init(first)
    local level = nil
    if first then
        level = 1
    end

    return {
        level = level,
        lines = {},
        line_index = 0,
        line_counter = 0,
        valid = true,
        type = "Floor"
    }
end


local function get_floor(subfactory_id, id)
    return global.factory.subfactories[subfactory_id].Floor.datasets[id]
end


function Floor.get_level(subfactory_id, id)
    return get_floor(subfactory_id, id).level
end

function Floor.set_level(subfactory_id, id, level)
    get_floor(subfactory_id, id).level = level
end


function Floor.add_line(subfactory_id, id, line)
    local self = get_floor(subfactory_id, id)
    self.line_index = self.line_index + 1
    self.line_counter = self.line_counter + 1
    line.gui_position = self.line_counter
    line.id = self.line_index
    self.lines[self.line_index] = line
    return self.line_index
end

function Floor.delete_line(subfactory_id, id, line_id)
    local self = get_floor(subfactory_id, id)
    self.line_counter = self.line_counter - 1
    data_util.update_positions(self.lines, self.lines[line_id].gui_position)
    self.lines[line_id] = nil
end


function Floor.get_line_count(subfactory_id, id)
    return get_floor(subfactory_id, id).line_counter
end

function Floor.get_line(subfactory_id, id, line_id)
    return get_floor(subfactory_id, id).lines[line_id]
end

-- Returns line id's in order by position (-> [gui_position] = id)
function Floor.get_lines_in_order(subfactory_id, id)
    return data_util.order_by_position(get_floor(subfactory_id, id).lines)
end


function Floor.is_valid(subfactory_id, id)
    return get_floor(subfactory_id, id).valid
end

-- Updates validity values of the datasets of all data_types
function Floor.check_validity(subfactory_id, id)
    local self = get_floor(subfactory_id, id)
    for line_id, _ in pairs(self.lines) do
        if not Line.check_validity(subfactory_id, id, line_id) then
            self.valid = false
            return
        end
    end
    self.valid = true
end

-- Removes all invalid datasets from the given floor
function Floor.remove_invalid_datasets(subfactory_id, id)
    local self = get_floor(subfactory_id, id)
    for line_id, line in pairs(self.lines) do
        if not line.valid then
            Floor.delete(subfactory_id, id, line_id)
        end
    end
    self.valid = true
end


function Floor.shift(subfactory_id, id, line_id, direction)
    local self = get_floor(subfactory_id, id)
    data_util.shift_position(self.floors, line_id, direction, self.counter)
end
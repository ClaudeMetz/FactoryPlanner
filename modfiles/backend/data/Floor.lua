local Object = require("backend.data.Object")
local Line = require("backend.data.Line")

---@alias LineObject Line | Floor
---@alias LineParent Factory | Floor

---@class Floor: Object, ObjectMethods
---@field class "Floor"
---@field parent LineParent
---@field level integer
---@field first_line LineObject?
---@field first_product SimpleItem?
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field energy_consumption number
---@field pollution number
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@return Floor
local function init(level)
    local object = Object.init({
        level = level,
        first_line = nil,

        first_product = nil,
        first_byproduct = nil,
        first_ingredient = nil,
        energy_consumption = 0,
        pollution = 0,
    }, "Floor", Floor)  --[[@as Floor]]
    return object
end


function Floor:index()
    OBJECT_INDEX[self.id] = self
    for line in self:iterator() do line:index() end
end

function Floor:cleanup()
    OBJECT_INDEX[self.id] = nil
    for line in self:iterator() do line:cleanup() end
end


---@param line LineObject
---@param relative_object LineObject?
---@param direction NeighbourDirection?
function Floor:insert(line, relative_object, direction)
    line.parent = self
    self:_insert(line, relative_object, direction)
end

---@param line LineObject
function Floor:remove(line)
    line:cleanup()
    self:_remove(line)

    -- Convert floor to line in parent if only defining line remains
    if self.level > 1 and self.first_line.next == nil then
        local parent_floor = self.parent  --[[@as Floor]]
        parent_floor:insert(self.first_line, self, "next")
        parent_floor:remove(self)
    end
end


---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot LineObject?
---@return fun(): LineObject?
function Floor:iterator(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_line)
    return self:_iterator(pivot_object, filter, direction)
end


---@return boolean any_removed
function Floor:remove_consuming_lines()
    local any_removed = false
    for line in self:iterator() do
        if line.class == "Floor" then
            any_removed = line:remove_consuming_lines() or any_removed
        elseif line.production_type == "consume" then
            self:remove(line)
            any_removed = true
        end
    end
    return any_removed
end


---@alias PackedLineObject PackedLine | PackedFloor

---@class PackedFloor: PackedObject
---@field class "Floor"
---@field level integer
---@field lines PackedLineObject[]?

---@return PackedFloor packed_self
function Floor:pack()
    return {
        class = self.class,
        level = self.level,
        lines = self:_pack(self.first_line)
    }
end

---@param packed_self PackedFloor
---@return Floor floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.level)

    local function unpacker(line) return (line.class == "Floor") and unpack(line) or Line.unpack(line) end
    unpacked_self.first_line = Object.unpack(packed_self.lines, unpacker, unpacked_self)  --[[@as LineObject]]

    return unpacked_self
end

---@return boolean valid
function Floor:validate()
    self.valid = self:_validate(self.first_line)
    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Floor:repair(player)
    -- TODO check how this works with subfloors, and the first line being invalid
    self:_repair(self.first_line, player)  -- always makes it valid

    self.valid = true
    return self.valid
end

return {init = init, unpack = unpack}

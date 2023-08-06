---@alias ObjectID integer

---@class Object
---@field id ObjectID
---@field class string
---@field valid boolean
---@field parent Object?
---@field first Object?
---@field next Object?
---@field previous Object?

---@class ObjectMethods
local methods = {}

local Object = {}  -- class annotation purposefully not attached

---@param data table
---@param class string
---@param metatable table
---@return Object
function Object.init(data, class, metatable)
    global.current_ID = global.current_ID + 1

    local object = ftable.shallow_merge{
        {
            id = global.current_ID,
            class = class,
            valid = true,
            parent = nil,
            next = nil,
            previous = nil
        },
        data
    }

    setmetatable(object, metatable)
    OBJECT_INDEX[object.id] = object

    return object
end

---@return ObjectMethods
function Object.methods()
    return ftable.shallow_copy(methods)
end


---@alias ObjectFilter {id: integer, archived: boolean}
local filter_options = {"id", "archived", "proto"}

---@param object Object
---@param filter ObjectFilter?
---@return boolean matched
local function match(object, filter)
    if filter == nil then return true end

    for _, option in pairs(filter_options) do
        -- Only match as filtered if object property is explicitly filtered out
        if filter[option] ~= nil and object[option] ~= filter[option] then
            return false
        end
    end

    return true
end


---@alias NeighbourDirection "next" | "previous"

---@private
---@param pivot Object?
---@param direction NeighbourDirection?
---@return Object? pivot
function methods:_actual_pivot(pivot, direction)
    if direction ~= nil and pivot ~= nil then
        if pivot[direction] ~= nil then return pivot[direction]
        else return nil end  -- nothing exists in this direction
    else
        return self.first
    end
end


---@protected
---@param new_object Object
---@param relative_object Object?
---@param direction NeighbourDirection?
function methods:_insert(new_object, relative_object, direction)
    if self.first == nil then
        self.first = new_object
    else
        if relative_object == nil then  -- no relative object means append
            relative_object, direction = self.first, "next"
            while relative_object.next ~= nil do
                relative_object = relative_object.next
            end
        end
        ---@cast relative_object -nil
        ---@cast direction -nil

        -- Make sure list header is adjusted if necessary
        if direction == "previous" and relative_object.previous == nil then
            self.first = new_object
        end

        -- Don't ask how I got to this, but it checks out
        local other_direction = (direction == "next") and "previous" or "next"
        if relative_object[direction] ~= nil then
            new_object[direction] = relative_object[direction]
            relative_object[direction][other_direction] = new_object
        end

        new_object[other_direction] = relative_object
        relative_object[direction] = new_object
    end
end

---@protected
---@param object Object
function methods:_remove(object)
    if object.previous == nil then
        self.first = object.next
        if object.next then object.next.previous = nil end
    else
        object.previous.next = object.next
        if object.next then object.next.previous = object.previous end
    end
    object.next, object.previous = nil, nil  -- so the object can be re-used elsewhere
end

---@protected
---@param object Object
---@param new_object Object
function methods:_replace(object, new_object)
    if object.previous == nil then
        self.first = new_object
    else
        new_object.previous = object.previous
        object.previous.next = new_object
    end
    if object.next then
        new_object.next = object.next
        object.next.previous = new_object
    end
end


---@protected
---@param object Object
---@param direction NeighbourDirection
---@param spots integer?
---@param filter ObjectFilter?
function methods:_shift(object, direction, spots, filter)
    spots = spots or math.huge  -- no spots means shift to end
    local spots_moved = 0

    local next_object = object
    while spots_moved < spots and next_object[direction] ~= nil do
        next_object = next_object[direction]
        local matched = match(next_object, filter)
        if matched then spots_moved = spots_moved + 1 end
    end

    if next_object.id ~= object.id then  -- only move if necessary
        self:_remove(object)
        self:_insert(object, next_object, direction)
    end
end


---@protected
---@param filter ObjectFilter
---@param pivot Object?
---@param direction NeighbourDirection?
---@return Object? object
function methods:_find(filter, pivot, direction)
    local next_object = self:_actual_pivot(pivot, direction)
    while next_object ~= nil do
        if match(next_object, filter) then return next_object end
        next_object = next_object[direction or "next"]
    end
    return nil
end

---@protected
---@param filter ObjectFilter?
---@param pivot Object?
---@param direction NeighbourDirection?
---@return Object? last_object
function methods:_find_last(filter, pivot, direction)
    local last_object = self:_actual_pivot(pivot, direction)
    while last_object ~= nil do
        local matched = match(last_object, filter)
        if matched then last_object = last_object[direction or "next"] end
    end
    return last_object
end


---@protected
---@param filter ObjectFilter?
---@param pivot Object?
---@param direction NeighbourDirection?
---@return fun(): Object?
function methods:_iterator(filter, pivot, direction)
    local next_object = self:_actual_pivot(pivot, direction)
    return function()
        while next_object ~= nil do
            local matched = match(next_object, filter)
            local current_object = next_object
            next_object = next_object[direction or "next"]
            if matched then return current_object end
        end
    end
end

---@protected
---@param filter ObjectFilter?
---@param pivot Object?
---@param direction NeighbourDirection?
---@return number count
function methods:_count(filter, pivot, direction)
    local count = 0
    for _ in self:_iterator(filter, pivot, direction) do
        count = count + 1
    end
    return count
end


---@class PackedObject
---@field class string

---@protected
---@param first_object Object?
---@return PackedObject[] packed_objects
function methods:_pack(first_object)
    local packed_objects = {}
    for object in self:_iterator(nil, first_object) do
        table.insert(packed_objects, object:pack())
    end
    return packed_objects
end

---@protected
---@param packed_objects PackedObject[]
---@param unpacker fun(item: PackedObject): Object
---@return Object? first_object
function Object.unpack(packed_objects, unpacker, parent)
    local first_object, latest_object = nil, nil
    for _, packed_object in pairs(packed_objects) do
        local object = unpacker(packed_object)
        object.parent = parent

        if not first_object then
            first_object = object
        else
            latest_object.next = object
            object.previous = latest_object
        end
        latest_object = object
    end
    return first_object
end


---@protected
---@param first_object Object?
---@return boolean valid
function methods:_validate(first_object)
    local valid = true
    for object in self:_iterator(nil, first_object) do
        -- Stays true until a single dataset is invalid, then stays false
        valid = object:validate() and valid
    end
    return valid
end

---@protected
---@param first_object Object?
function methods:_repair(first_object, player)
    for object in self:_iterator(nil, first_object) do
        if not object.valid and not object:repair(player) then
            object.parent:remove(object)
        end
    end
end

return Object

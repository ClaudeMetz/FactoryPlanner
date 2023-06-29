---@alias ObjectID integer

---@class Object
---@field id ObjectID
---@field class string
---@field valid boolean
---@field parent Object?
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

    local object = fancytable.shallow_merge{
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
    return fancytable.shallow_copy(methods)
end


---@alias NeighbourDirection "next" | "previous"


---@alias ObjectFilter {id: integer, archived: boolean}
local filter_options = {"id", "archived"}

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

---@protected
---@param direction NeighbourDirection?
---@param pivot Object?
---@param first Object?
---@return Object? pivot
function methods:_determine_pivot(direction, pivot, first)
    if direction ~= nil and pivot ~= nil then
        if pivot[direction] ~= nil then return pivot[direction]
        else return nil end  -- nothing exists in this direction
    else
        return first
    end
end


---@protected
---@param new_object Object
---@param relative_object Object?
---@param direction NeighbourDirection?
function methods:_insert(new_object, relative_object, direction)
    local first = "first_" .. new_object.class:lower()

    if self[first] == nil then
        self[first] = new_object
    else
        if relative_object == nil then  -- no relative object means append
            relative_object, direction = self[first], "next"
            while relative_object.next ~= nil do
                relative_object = relative_object.next
            end
        end
        ---@cast relative_object -nil
        ---@cast direction -nil

        -- Make sure list header is adjusted if necessary
        if direction == "previous" and relative_object.previous == nil then
            self[first] = new_object
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
        self["first_" .. object.class:lower()] = object.next
        if object.next then object.next.previous = nil end
    else
        object.previous.next = object.next
        if object.next then object.next.previous = object.previous end
    end
    object.next, object.previous = nil, nil
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
---@param pivot Object?
---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@return Object? object
function methods:_find(pivot, filter, direction)
    local next_object = pivot
    while next_object ~= nil do
        if match(next_object, filter) then return next_object end
        next_object = next_object[direction or "next"]
    end
    return nil
end


---@protected
---@param first_object Object?
---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@return function iterator
function methods:_iterator(first_object, filter, direction)
    local next_object = first_object
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
---@param first_object Object?
---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@return number count
function methods:_count(first_object, filter, direction)
    local count = 0
    for _ in self:_iterator(first_object, filter, direction) do
        count = count + 1
    end
    return count
end


---@protected
---@param first_object Object?
---@param filter ObjectFilter?
function methods:_validate(first_object, filter)
    for object in self:_iterator(first_object, filter) do
        object:validate()
    end
end

return Object

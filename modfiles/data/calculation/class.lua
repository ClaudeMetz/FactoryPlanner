--- Helper for generate OOP-style data structures.
-- @module class
-- @license MIT
-- @author B_head

local M = {}

local function noop()
    -- no operation.
end

local function create_metatable(name, prototype, extend_class)
    local super_metatable = getmetatable(extend_class) or {}
    local super_prototype = super_metatable.__prototype
    setmetatable(prototype, {
        __index = super_prototype -- Constructing prototype chains.
    })
    local ret = {
        __new = noop
    }
    for k, v in pairs(super_metatable) do
        ret[k] = v
    end
    ret.__type = name
    ret.__prototype = prototype
    ret.__super_prototype = super_prototype
    ret.__extend = extend_class
    ret.__index = prototype -- Assign a prototype to instances.
    for k, v in pairs(prototype) do
        if k:sub(1, 2) == "__" then
            ret[k] = v
        end
    end
    return ret
end

local function create_instance(class_object, ...)
    local mt = getmetatable(class_object)
    local ret = {}
    setmetatable(ret, mt)
    mt.__new(ret, ...)
    return ret
end

--- Create class object.
-- @tparam string name Name of the class type.
-- @tparam table prototype A table that defines methods, meta-methods, and constants.
-- @tparam table static A table that defines static functions.
-- @param extend_class Class object to inherit from.
-- @return Class object.
function M.class(name, prototype, static, extend_class)
    static = static or {}
    setmetatable(static, {
        __call = create_instance,
        -- Overrides the metatable returned by getmetatable(class_object).
        __metatable = create_metatable(name, prototype, extend_class), 
    })
    return static -- Return as class_object.
end

--- Return name of the class type.
-- @param value Class object.
-- @return Class name.
function M.class_type(value)
    local mt = getmetatable(value)
    return mt and mt.__type
end

--- Return a prototype table.
-- @param value Class object.
-- @return Prototype table.
function M.prototype(value)
    local mt = getmetatable(value)
    return mt and mt.__prototype
end

--- Return a prototype table of the superclass.
-- @param value Class object.
-- @return Prototype table.
function M.super(value)
    local mt = getmetatable(value)
    return mt and mt.__super_prototype
end

--- Restore methods, meta-methods, and constants in the instance table.
-- @tparam table plain_table An instance table to restore.
-- @param class_object Class object that defines methods, meta-methods, and constants.
-- @return Instance table.
function M.resetup(plain_table, class_object)
    local mt = getmetatable(class_object)
    setmetatable(plain_table, mt)
    return plain_table
end

return M
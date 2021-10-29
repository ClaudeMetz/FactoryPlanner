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

function M.class(name, prototype, static, extend_class)
    static = static or {}
    setmetatable(static, {
        __call = create_instance,
        -- Overrides the metatable returned by getmetatable(class_object).
        __metatable = create_metatable(name, prototype, extend_class), 
    })
    return static -- Return as class_object.
end

function M.class_type(value)
    local mt = getmetatable(value)
    return mt and mt.__type
end

function M.prototype(value)
    local mt = getmetatable(value)
    return mt and mt.__prototype
end

function M.super(value)
    local mt = getmetatable(value)
    return mt and mt.__super_prototype
end

function M.resetup(plain_table, class_object)
    local mt = getmetatable(class_object)
    setmetatable(plain_table, mt)
    return plain_table
end

return M
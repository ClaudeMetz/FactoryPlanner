cutil = {}

-- Splits given string
function cutil.split(s, separator)
    local r = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
        if tonumber(token) ~= nil then
            token = tonumber(token)
        end
        table.insert(r, token) 
    end
    return r
end

-- Shallowly and naively copys the base level of the given table
function cutil.shallowcopy(table)
    local copy = {}
    for key, value in pairs(table) do
        copy[key] = value
    end
    return copy
end

-- Deepcopies given table, excluding certain attributes (cribbed from core.lualib)
function cutil.deepcopy(object)
    local excluded_attributes = {proto=true}

    local lookup_table = {}
    local function _copy(name, object)
        if type(object) ~= "table" then
            return object
        -- don't copy the excluded attributes
        elseif excluded_attributes[name] then
            return object
        -- don't copy factorio rich objects
        elseif object.__self then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy("", index)] = _copy(index, value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy("", object)
end
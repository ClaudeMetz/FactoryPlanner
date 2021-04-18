local epsilon_table = {}
epsilon_table.mt = {}

function epsilon_table.convert(number, level)
    level = level or 0
    local new = {[level] = number}
    setmetatable(new, epsilon_table.mt)
    return new
end

function epsilon_table.ensure_is_epsilon(number)
    if type(number) == "number" then
        return epsilon_table.convert(number)
    elseif type(number) ~= "table" or getmetatable(number) ~= epsilon_table.mt then
        error("arg must be an epsilon_number")
    end
    return number
end

function epsilon_table.copy(epsilon)
    epsilon = epsilon_table.ensure_is_epsilon(epsilon)
    local copy = epsilon_table.convert(0)
    for i,k in pairs(epsilon) do
        copy[i] = k
    end
    return copy
end

function epsilon_table.reduce_to_zero(epsilon)
    for i,k in pairs(epsilon) do
        if math.abs(k) < 1e-5 then
            epsilon[i] = nil
        end
    end
end

function epsilon_table.mt.__add(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local new = epsilon_table.convert(0)
    for i, v in pairs(lhs) do
        new[i] = v
    end
    for i, v in pairs(rhs) do
        new[i] = (new[i] or 0) + rhs[i]
    end
    return new
end

function epsilon_table.mt.__sub(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local new = epsilon_table.convert(0)
    for i, v in pairs(lhs) do
        new[i] = v
    end
    for i, v in pairs(rhs) do
        new[i] = (new[i] or 0) - rhs[i]
    end
    return new
end

function epsilon_table.mt.__unm(number)
    local new = epsilon_table.convert(0)
    for i,v in pairs(number) do
        new[i] = -v
    end
    return new
end

function epsilon_table.mt.__mul(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local new = epsilon_table.convert(0)
    for lhs_index,lhs_value in pairs(lhs) do
        for rhs_index,rhs_value in pairs(rhs) do
            new[lhs_index+rhs_index] = (new[lhs_index+rhs_index] or 0) + lhs_value*rhs_value
        end
    end
    return new
end

function epsilon_table.mt.__div(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local new = epsilon_table.convert(0)
    for lhs_index,lhs_value in pairs(lhs) do
        for rhs_index,rhs_value in pairs(rhs) do
            new[lhs_index-rhs_index] = (new[lhs_index-rhs_index] or 0) + lhs_value/rhs_value
        end
    end
    return new
end

function epsilon_table.mt.__eq(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    for i,v in pairs(lhs) do
        if rhs[i] ~= v and not (rhs[i] == nil and v == 0) then
            return false
        end
    end
    for i,v in pairs(rhs) do
        if lhs[i] ~= v and not (lhs[i] == nil and v == 0) then
            return false
        end
    end
    return true
end

function epsilon_table.mt.__lt(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local min, max = nil, nil
    for i,_ in pairs(lhs) do
        if min == nil or i < min then
            min = i
        end
        if max == nil or i > max then
            max = i
        end
    end
    for i,_ in pairs(rhs) do
        if min == nil or i < min then
            min = i
        end
        if max == nil or i > max then
            max = i
        end
    end
    min = min or 0
    max = max or 0
    for i=min,max do
        if (lhs[i] or 0) < (rhs[i] or 0) then
            return true
        end
        if (lhs[i] or 0) > (rhs[i] or 0) then
            return false
        end
    end
    return false
end

function epsilon_table.mt.__le(lhs, rhs)
    lhs = epsilon_table.ensure_is_epsilon(lhs)
    rhs = epsilon_table.ensure_is_epsilon(rhs)
    local min, max = nil, nil
    for i,_ in pairs(lhs) do
        if min == nil or i < min then
            min = i
        end
        if max == nil or i > max then
            max = i
        end
    end
    for i,_ in pairs(rhs) do
        if min == nil or i < min then
            min = i
        end
        if max == nil or i > max then
            max = i
        end
    end
    min = min or 0
    max = max or 0
    for i=min,max do
        if (lhs[i] or 0) < (rhs[i] or 0) then
            return true
        end
        if (lhs[i] or 0) > (rhs[i] or 0) then
            return false
        end
    end
    return true
end

function epsilon_table.mt.__tostring(number)
    local min, max = nil, nil
    for i,_ in pairs(number) do
        if min == nil or i < min then
            min = i
        end
        if max == nil or i > max then
            max = i
        end
    end
    min = min or 0
    max = max or 0
    local is_first = true
    local s = ""
    for i=min,max do
        if number[i] and number[i] ~= 0 then
            if not is_first and number[i] > 0 then
                s=s.."+"
            end
            s=s..tostring(number[i])
            if i < 0 then
                s = s.."M"
                if i < -1 then
                    s = s.."^"..tostring(math.abs(i))
                end
            end
            if i > 0 then
                s = s.."ε"
                if i > 1 then
                    s = s.."^"..tostring(math.abs(i))
                end
            end

            is_first = false
        end
    end
    if s == "" then
        s = "0"
    end
    s = "("..s..")"
    return s
end

return epsilon_table

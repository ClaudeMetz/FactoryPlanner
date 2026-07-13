local _math = {}


---Performs `a - b` while correcting floating point errors
---@param a number
---@param b number
---@return number
function _math.safe_sub(a, b)
    local c = a - b
    local error = math.max(math.abs(a), math.abs(b)) * MAGIC_NUMBERS.double_margin_of_error
    if c < error and c > -error then c = 0 end
    return c
end


return _math

local _math = {}


---Performs `a - b` while correcting floating point errors
---@param a number
---@param b number
---@return number
function _math.safe_sub(a, b)
    local c = a - b
    if c < MAGIC_NUMBERS.margin_of_error and c > -MAGIC_NUMBERS.margin_of_error then return 0 end
    return c
end


return _math

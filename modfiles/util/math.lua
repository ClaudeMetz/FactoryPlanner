local math = {
    array = {}
}


---@alias Array<K: any> {K: number}


---@param array Array<any>
---@param key any
---@param value number
---@return number
function math.array.add(array, key, value)
    array[key] = array[key] ~= nil and array[key] + value or value
    return array[key]
end


return math
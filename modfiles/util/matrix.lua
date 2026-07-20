local _matrix = {}


--- Performs `M * v`
---@param matrix number[][] column-major order
---@param vector number[]
---@return number[]
function _matrix.right_mult_cmo(matrix, vector)
    local result = {}  ---@type number[]
    for i = 1, #matrix[1] do
        result[i] = 0.0
    end
    for j = 1, #matrix do
        if vector[j] ~= 0 then
            for i = 1, #matrix[j] do
                if matrix[j][i] ~= 0 then
                    ---@diagnostic disable: need-check-nil
                    result[i] = result[i] + vector[j] * matrix[j][i]
                end
            end
        end
    end

    return result
end


--- Performs `v^T * M`
---@param vector number[]
---@param matrix number[][] column-major order
---@return number[]
function _matrix.left_mult_cmo(vector, matrix)
    local result = {}  ---@type number[]
    for j = 1, #matrix do
        result[j] = 0.0
    end
    for i = 1, #matrix[1] do
        if vector[i] ~= 0 then
            for j = 1, #matrix do
                if matrix[j][i] ~= 0 then
                    ---@diagnostic disable: need-check-nil
                    result[j] = result[j] + vector[i] * matrix[j][i]
                end
            end
        end
    end

    return result
end


return _matrix

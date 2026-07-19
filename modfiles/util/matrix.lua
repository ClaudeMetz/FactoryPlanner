local _matrix = {}


--- Multiplies `M[x]` with a scaling factor `k` (`M[x] = k * M[x]`)
---@param matrix number[][] M
---@param x integer x
---@param scalar number k
function _matrix.row_mult(matrix, x, scalar)
    for j = 1, #matrix[x] do matrix[x][j] = scalar * matrix[x][j] end
end


--- Subtracts `M[y]` from `M[x]` after scaling with `k` (`M[x] = M[x] - k * M[y]`)
---@param matrix number[][] M
---@param x integer x
---@param y integer y
---@param scalar number k
function _matrix.row_subtract(matrix, x, y, scalar)
    for j = 1, #matrix[x] do
        ---@diagnostic disable: need-check-nil
        matrix[x][j] = lib.math.safe_sub(matrix[x][j], scalar * matrix[y][j])
        -- matrix[x][j] = matrix[x][j] - scalar * matrix[y][j]
    end
end


--- Performs `M * v`
---@param matrix number[][]
---@param vector number[]
---@return number[]
function _matrix.right_mult(matrix, vector)
    local result = {}  ---@type number[]
    for i = 1, #matrix do
        result[i] = 0.0
        for j = 1, #matrix do
            ---@diagnostic disable: need-check-nil
            result[i] = result[i] + vector[j] * matrix[i][j]
        end
    end

    return result
end


--- Performs `v^T * M`
---@param vector number[]
---@param matrix number[][]
---@return number[]
function _matrix.left_mult(vector, matrix)
    local result = {}  ---@type number[]
    for j = 1, #matrix[1] do
        result[j] = 0.0
        for i = 1, #matrix do
            ---@diagnostic disable: need-check-nil
            result[j] = result[j] + vector[i] * matrix[i][j]
        end
    end

    return result
end


--- Performs a pivot operation on the matrix.
--- Row `M[i]` is first divided by the pivot value `M[i][j]`,
--- then every other row is subtracted by the pivot row `m[i]`
--- scaled by their value in the pivot column (`M[x][j]`)
--- @param matrix number[][] M
--- @param row integer i
--- @param column integer j
function _matrix.pivot(matrix, row, column)
    ---@diagnostic disable: need-check-nil
    _matrix.row_mult(matrix, row, 1 / matrix[row][column])
    matrix[row][column] = 1  --improve precision
    for i = 1, #matrix do
        if i ~= row then
            _matrix.row_subtract(matrix, i, row, matrix[i][column]--[[@as number]])
            matrix[i][column] = 0  --improve precision
        end
    end
end


return _matrix

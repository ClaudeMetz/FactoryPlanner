local _matrix = {}


--- Multiplies `M[x]` with a scaling factor `k` (`M[x] = k * M[x]`)
---@param matrix number[][] M
---@param x integer x
---@param scalar number k
function _matrix.row_mult(matrix, x, scalar)
    if not matrix[x] then return end
    for j = 1, #matrix[x] do matrix[x][j] = scalar * matrix[x][j] end
end


--- Subtracts `M[y]` from `M[x]` after scaling with `k` (`M[x] = M[x] - k * M[y]`)
---@param matrix number[][] M
---@param x integer x
---@param y integer y
---@param scalar number k
function _matrix.row_subtract(matrix, x, y, scalar)
    if not matrix[x] or not matrix[y] then return end
    if scalar == 0 then return end
    local cols = math.min(#matrix[x], #matrix[y])
    for j = 1, cols do
        matrix[x][j] = lib.math.safe_sub(matrix[x][j]--[[@as number]], scalar * matrix[y][j]--[[@as number]])
    end
end


--- Performs a pivot operation on the matrix.
--- Row `M[i]` is first divided by the pivot value `M[i][j]`,
--- then every other row is subtracted by the pivot row `m[i]`
--- scaled by their value in the pivot column (`M[x][j]`)
--- @param matrix number[][] M
--- @param row integer i
--- @param column integer j
function _matrix.pivot(matrix, row, column)
    if row > #matrix or not matrix[row] then return end
    if column > #matrix[row] then return end
    _matrix.row_mult(matrix, row, 1 / matrix[row][column]--[[@as number]])
    matrix[row][column] = 1  --improve precision
    for i = 1, #matrix do
        if i ~= row then
            _matrix.row_subtract(matrix, i, row, matrix[i][column]--[[@as number]])
        end
    end
end


return _matrix

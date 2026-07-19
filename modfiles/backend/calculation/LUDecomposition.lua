---@class LUDecomposition
---@field lu_matrix number[][] `U` when `row >= column`, and `L` otherwise
---@field p_vector integer[] shift vector representing `P`
---@field p_transposed integer[] shift vector representing `P^T`
local LUDecomposition = {}
LUDecomposition.__index = LUDecomposition

---@class FTUpdate
---@field vector number[]
---@field row integer


--- Performs LU decomposition `L U = P A`
---@param matrix number[][] becomes the `LU` combined matrix
---@return LUDecomposition
function LUDecomposition:init(matrix)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        lu_matrix = matrix,
        p_vector = {},
        p_transposed = {},
    }  ---@type LUDecomposition

    setmetatable(o, self)
    -- Initialize the matrices and the permutation vectors
    for i = 1, #o.lu_matrix do
        o.p_vector[i] = i
        o.p_transposed[i] = i
    end

    for k = 1, #o.lu_matrix - 1 do
        ---@diagnostic disable: undefined-field, need-check-nil

        -- Find pivot
        local pivot_row = k
        local max = math.abs(o.lu_matrix[k][k]--[[@as number]])
        for i = k + 1, #o.lu_matrix do
            local cell = math.abs(o.lu_matrix[i][k]--[[@as number]])
            if cell > max then
                max = cell
                pivot_row = i
            end
        end

        if max > 0 then
            -- Permute
            if pivot_row ~= k then
                local temp_lu = o.lu_matrix[pivot_row]
                o.lu_matrix[pivot_row] = o.lu_matrix[k]
                o.lu_matrix[k] = temp_lu

                local temp_p = o.p_vector[pivot_row]  ---@as integer
                o.p_vector[pivot_row] = o.p_vector[k]  ---@as integer
                o.p_vector[k] = temp_p

                o.p_transposed[o.p_vector[pivot_row]] = pivot_row
                o.p_transposed[o.p_vector[k]] = k
            end

            -- Row-subtract below the pivot
            for i = k + 1, #o.lu_matrix do
                local scalar = o.lu_matrix[i][k] / o.lu_matrix[k][k]
                o.lu_matrix[i][k] = scalar
                if o.lu_matrix[i][k] ~= 0 then
                    for j = k + 1, #o.lu_matrix do
                        o.lu_matrix[i][j] = o.lu_matrix[i][j] - scalar * o.lu_matrix[k][j]
                    end
                end
            end
        else
            -- Vector is degenerate. Just put a big number here and hope noting goes wrong
            o.lu_matrix[k][k] = 1e100
            for i = k + 1, #o.lu_matrix do
                o.lu_matrix[i][k] = 0
            end
        end
    end

    return o
end


--- Calculates `x` vector where `x^T A = v^T`.
--- After decomposition, the equation becomes `(P x)^T LU = v^T`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_left(vector)
    -- Solve `y^T U = v^T`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.lu_matrix do
        ---@diagnostic disable: undefined-field, need-check-nil
        y_vector[k] = vector[k]
        for i = 1, k - 1 do
            if y_vector[i] ~= 0 and self.lu_matrix[i][k] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.lu_matrix[i][k]
            end
        end
        y_vector[k] = y_vector[k] / self.lu_matrix[k][k]
    end

    ---@TODO: solve for update vectors

    -- Solve `(P x)^T L = y^T`
    local x_vector = {}  ---@type number[]
    for k = #self.lu_matrix, 1, -1 do
        ---@diagnostic disable: undefined-field, inject-field, need-check-nil
        local cell = y_vector[k]
        for i = k + 1, #self.lu_matrix do
            if x_vector[self.p_vector[i]] ~= 0 and self.lu_matrix[i][k] then
                cell = cell - x_vector[self.p_vector[i]] * self.lu_matrix[i][k]
            end
        end
        x_vector[self.p_vector[k]] = cell
    end

    return x_vector
end


--- Calculates `x` vector where `A x = v`.
--- After decomposition, the equation becomes `LU x = P v`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_right(vector)
    -- Solve `L y = P v`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.lu_matrix do
        ---@diagnostic disable: undefined-field, need-check-nil
        y_vector[k] = vector[self.p_vector[k]]
        for i = 1, k - 1 do
            if  y_vector[i] ~= 0 and self.lu_matrix[k][i] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.lu_matrix[k][i]
            end
        end
    end

    ---@TODO: solve for update vectors

    -- Solve `U x = y`
    local x_vector = {}  ---@type number[]
    for k = #self.lu_matrix, 1, -1 do
        ---@diagnostic disable: undefined-field, need-check-nil
        local cell = y_vector[k]
        for i = k + 1, #self.lu_matrix do
            if x_vector[i] ~= 0 and self.lu_matrix[k][i] ~= 0 then
                cell = cell - x_vector[i] * self.lu_matrix[k][i]
            end
        end
        x_vector[k] = cell / self.lu_matrix[k][k]
    end

    return x_vector
end


--- Perform `A = P^T LU` (for debugging)
---@return number[][]
function LUDecomposition:recompose()
    local result = {}  ---@type number[][]
    for i = 1, #self.lu_matrix do
        result[i] = {}
        for j = 1, #self.lu_matrix do
            result[i][j] = 0.0
            for k = 1, j do
                ---@diagnostic disable: undefined-field, need-check-nil
                local l_row = self.p_transposed[i]
                if l_row < k then
                    result[i][j] = result[i][j] + self.lu_matrix[l_row][k] * self.lu_matrix[k][j]
                elseif l_row == k then
                    result[i][j] = result[i][j] + self.lu_matrix[k][j]
                end
            end
        end
    end
    return result
end


return LUDecomposition

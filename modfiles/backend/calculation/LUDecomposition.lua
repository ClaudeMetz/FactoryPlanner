---@class LUDecomposition
---@field l_matrix number[][] `L`
---@field u_matrix number[][] `U`
---@field r_updates FTUpdate[] Forrest-Tomlin update vectors
---@field p_vector integer[] shift vector representing `P`
---@field p_transposed integer[] shift vector representing `P^T`
local LUDecomposition = {}
LUDecomposition.__index = LUDecomposition

---@class FTUpdate
---@field vector number[]
---@field row integer


--- Performs LU decomposition `L U = P A`
---@param matrix number[][]
---@return LUDecomposition
function LUDecomposition:init(matrix)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        l_matrix = {},
        u_matrix = lib.flib.deep_copy(matrix),
        r_updates = {},
        p_vector = {},
        p_transposed = {},
    }  ---@type LUDecomposition

    setmetatable(o, self)
    -- Initialize the matrices and the permutation vectors
    for i = 1, #o.u_matrix do
        o.l_matrix[i] = {}
        o.p_vector[i] = i
        o.p_transposed[i] = i
    end

    for k = 1, #o.u_matrix - 1 do
        ---@diagnostic disable: undefined-field, need-check-nil

        -- Find pivot
        local pivot_row = k
        local max = math.abs(o.u_matrix[k][k]--[[@as number]])
        for i = k + 1, #o.u_matrix do
            local cell = math.abs(o.u_matrix[i][k]--[[@as number]])
            if cell > max then
                max = cell
                pivot_row = i
            end
        end

        -- Permute
        if pivot_row ~= k then
            local temp = o.p_vector[pivot_row]  ---@as integer
            o.p_vector[pivot_row] = o.p_vector[k]  ---@as integer
            o.p_vector[k] = temp

            o.p_transposed[o.p_vector[pivot_row]] = pivot_row
            o.p_transposed[o.p_vector[k]] = k

            local temp_u = o.u_matrix[pivot_row]
            o.u_matrix[pivot_row] = o.u_matrix[k]
            o.u_matrix[k] = temp_u

            local temp_l = o.l_matrix[pivot_row]
            o.l_matrix[pivot_row] = o.l_matrix[k]
            o.l_matrix[k] = temp_l
        end

        o.l_matrix[k][k] = 1

        -- Row-subtract below the pivot
        for i = k + 1, #o.u_matrix do
            local scalar = o.u_matrix[i][k] / o.u_matrix[k][k]
            o.l_matrix[i][k] = scalar
            if o.u_matrix[i][k] ~= 0 then
                o.u_matrix[i][k] = 0
                for j = k + 1, #o.u_matrix do
                    o.u_matrix[i][j] = o.u_matrix[i][j] - scalar * o.u_matrix[k][j]
                end
            end
        end
    end

    o.l_matrix[#o.l_matrix][#o.l_matrix] = 1

    return o
end


--- Calculates `x` vector where `x^T A = v^T`.
--- After decomposition, the equation becomes `(P x)^T LRU = v^T`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_left(vector)
    -- Solve `y^T U = v^T`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.u_matrix do
        ---@diagnostic disable: undefined-field, need-check-nil
        y_vector[k] = vector[k]
        for i = 1, k - 1 do
            y_vector[k] = y_vector[k] - y_vector[i] * self.u_matrix[i][k]
        end
        y_vector[k] = y_vector[k] / self.u_matrix[k][k]
    end

    ---@TODO: solve for update vectors

    -- Solve `(P x)^T L = y^T`
    local x_vector = {}  ---@type number[]
    for k = #self.l_matrix, 1, -1 do
        ---@diagnostic disable: undefined-field, inject-field, need-check-nil
        local cell = y_vector[k]
        for i = k + 1, #self.l_matrix do
            cell = cell - x_vector[self.p_vector[i]] * self.l_matrix[i][k]
        end
        x_vector[self.p_vector[k]] = cell
    end

    return x_vector
end


--- Calculates `x` vector where `A x = v`.
--- After decomposition, the equation becomes `LRU x = P v`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_right(vector)
    -- Solve `L y = P v`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.l_matrix do
        ---@diagnostic disable: undefined-field, need-check-nil
        y_vector[k] = vector[self.p_vector[k]]
        for i = 1, k - 1 do
            y_vector[k] = y_vector[k] - y_vector[i] * self.l_matrix[k][i]
        end
    end

    ---@TODO: solve for update vectors

    -- Solve `U x = y`
    local x_vector = {}  ---@type number[]
    for k = #self.u_matrix, 1, -1 do
        ---@diagnostic disable: undefined-field, need-check-nil
        local cell = y_vector[k]
        for i = k + 1, #self.u_matrix do
            cell = cell - x_vector[i] * self.u_matrix[k][i]
        end
        x_vector[k] = cell / self.u_matrix[k][k]
    end

    return x_vector
end


--- Perform `A = P^T LRU` (for debugging)
---@return number[][]
function LUDecomposition:recompose()
    local result = {}  ---@type number[][]
    for i = 1, #self.u_matrix do
        result[i] = {}
        for j = 1, #self.u_matrix do
            result[i][j] = 0.0
            for k = 1, #self.u_matrix do
                ---@diagnostic disable: undefined-field
                result[i][j] = result[i][j] + (self.l_matrix[self.p_transposed[i]][k] or 0.0) * self.u_matrix[k][j]
            end
        end
    end
    return result
end


return LUDecomposition

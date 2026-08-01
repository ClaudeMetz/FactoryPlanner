---@class LUDecomposition
---@field u_matrix number[][] `U*` permuted upper triangular matrix where `U = P U*`
---@field l_matrix number[][] `L` lower unit triangular matrix
---@field p_vector integer[] row shift vector representing `P`
---@field q_vector integer[] column shift vector representing `Q`
---@field eta_updates EtaUpdate[] array of vectors representing `E_n^-1`
local LUDecomposition = {}
LUDecomposition.__index = LUDecomposition

---@class EtaUpdate
---@field vector number[]
---@field column integer

local USE_ROOK_PIVOTING = true


--- Performs LU decomposition `L U = P A Q`
---@param matrix number[][] column-major order square matrix
---@return LUDecomposition?
---@return integer? error_column
function LUDecomposition:init(matrix)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        u_matrix = {},
        l_matrix = {},
        p_vector = {},
        q_vector = {},
        eta_updates = {}
    }  ---@type LUDecomposition
    setmetatable(o, self)

    -- Initialize the matrices and the permutation vectors
    for i = 1, #matrix do
        o.p_vector[i] = i
        o.q_vector[i] = i
        o.u_matrix[i] = {}
        o.l_matrix[i] = {}
        for j = 1, #matrix do o.u_matrix[i][j] = matrix[j][i] end
        for j = 1, #matrix do o.l_matrix[i][j] = 0 end
    end

    for k = 1, #o.u_matrix - 1 do
        ---@diagnostic disable: need-check-nil
        local pk = o.p_vector[k]  ---@as integer
        local qk = o.q_vector[k]  ---@as integer

        -- Find pivot
        local pivot_row = k
        local pivot_col = k
        if USE_ROOK_PIVOTING then
            pivot_row, pivot_col = o:_rook_pivot_vertical(k, k, k, k)
        else
            local max = o.u_matrix[pk][k] > 0 and o.u_matrix[pk][k] or -o.u_matrix[pk][k]
            for i = k + 1, #o.u_matrix do
                local pi = o.p_vector[i]  ---@as integer
                local cell = o.u_matrix[pi][k] > 0 and o.u_matrix[pi][k] or -o.u_matrix[pi][k]
                if cell > max then
                    max = cell
                    pivot_row = i
                end
            end
        end

        -- Permute
        if pivot_row ~= k then
            local temp = o.l_matrix[pivot_row]
            o.l_matrix[pivot_row] = o.l_matrix[k]
            o.l_matrix[k] = temp

            pk = o.p_vector[pivot_row] or 0
            o.p_vector[pivot_row] = o.p_vector[k]  ---@as integer
            o.p_vector[k] = pk
        end
        if pivot_col ~= k then
            qk = o.q_vector[pivot_col] or 0
            o.q_vector[pivot_col] = o.q_vector[k]  ---@as integer
            o.q_vector[k] = qk
        end

        if o.u_matrix[pk][qk] ~= 0 then
            -- Row-subtract below the pivot
            for i = k + 1, #o.u_matrix do
                local pi = o.p_vector[i]  ---@as integer
                local scalar = o.u_matrix[pi][qk] / o.u_matrix[pk][qk]
                o.u_matrix[pi][qk] = 0
                o.l_matrix[i][k] = scalar
                if scalar ~= 0 then
                    for j = k + 1, #o.u_matrix do
                        local qj = o.q_vector[j]  ---@as integer
                        o.u_matrix[pi][qj] = o.u_matrix[pi][qj] - scalar * o.u_matrix[pk][qj]
                    end
                end
            end
        else
            -- Basis is unfeasible
            return nil, qk
        end
    end

    -- Fill the diagonal of the lower triangular matrix
    for k = 1, #o.l_matrix do o.l_matrix[k][k] = 1 end

    return o
end


--- Updates the decomposed matrix by replacing a column.
--- The updates are stored as eta factorizations
---@param vector number[] `v` where `A v = a` and `a` is the column entering the basis
---@param column integer
---@return boolean is_stable
function LUDecomposition:update(vector, column)
    local eta = {
        vector = {},
        column = column
    }  ---@type EtaUpdate

    -- Check for stability
    local scalar = vector[column]  ---@as number
    if scalar < MAGIC_NUMBERS.margin_of_error and
            scalar > -MAGIC_NUMBERS.margin_of_error then
        return false
    end

    -- Invert the vector
    for i = 1, #vector do
        if i == column then
            eta.vector[i] = 1 / scalar
        else
            eta.vector[i] = -vector[i] / scalar
        end
    end

    -- Add to the update list
    table.insert(self.eta_updates, eta)
    return true
end

--- Calculates `x` vector where `x^T A = v^T` (`A^T x = v`).
--- After decomposition, the equation becomes `x P^T LU Q^T E = v^T`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_left(vector)
    -- Solve `z^T E = v^T`
    local z_vector = {}
    for j = 1, #vector do z_vector[j] = vector[j] end
    for i = #self.eta_updates, 1, -1 do
        local eta = self.eta_updates[i]
        local dot = 0.0
        for j = 1, #z_vector do
            if z_vector[j] ~= 0 and eta.vector[j] ~= 0 then
                ---@diagnostic disable: need-check-nil
                dot = dot + z_vector[j] * eta.vector[j]
            end
        end
        z_vector[eta.column] = dot
    end

    -- Solve `y^T U = z^T Q`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.u_matrix do
        ---@diagnostic disable: need-check-nil
        local pk = self.p_vector[k]  ---@as integer
        local qk = self.q_vector[k]  ---@as integer
        y_vector[k] = z_vector[qk]
        for i = 1, k - 1 do
            local pi = self.p_vector[i]  ---@as integer
            if y_vector[i] ~= 0 and self.u_matrix[pi][qk] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.u_matrix[pi][qk]
            end
        end
        y_vector[k] = y_vector[k] / self.u_matrix[pk][qk]
    end

    -- Solve `x P^T L = y^T`
    local x_vector = {}  ---@type number[]
    for k = #self.l_matrix, 1, -1 do
        ---@diagnostic disable: need-check-nil
        local cell = y_vector[k]
        local pk = self.p_vector[k]  ---@as integer
        for i = k + 1, #self.l_matrix do
            local pi = self.p_vector[i]  ---@as integer
            if x_vector[pi] ~= 0 and self.l_matrix[i][k] ~= 0 then
                cell = cell - x_vector[pi] * self.l_matrix[i][k]
            end
        end
        x_vector[pk] = cell
    end

    return x_vector
end


--- Calculates `x` vector where `A x = v`.
--- After decomposition, the equation becomes `LU Q^T E x = P v`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_right(vector)
    -- Solve `L y = P v`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.l_matrix do
        ---@diagnostic disable: need-check-nil
        y_vector[k] = vector[self.p_vector[k]--[[@cast -nil]]]
        for i = 1, k - 1 do
            if  y_vector[i] ~= 0 and self.l_matrix[k][i] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.l_matrix[k][i]
            end
        end
    end

    -- Solve `U Q^T x = y`
    local x_vector = {}  ---@type number[]
    for k = #self.u_matrix, 1, -1 do
        ---@diagnostic disable: need-check-nil
        local pk = self.p_vector[k]  ---@as integer
        local qk = self.q_vector[k]  ---@as integer
        local cell = y_vector[k]
        for i = k + 1, #self.u_matrix do
            local qi = self.q_vector[i]  ---@as integer
            if x_vector[qi] ~= 0 and self.u_matrix[pk][qi] ~= 0 then
                cell = cell - x_vector[qi] * self.u_matrix[pk][qi]
            end
        end
        x_vector[qk] = cell / self.u_matrix[pk][qk]
    end

    -- Solve `E x* = x`
    for i = 1, #self.eta_updates do
        local eta = self.eta_updates[i]
        if x_vector[eta.column] > MAGIC_NUMBERS.margin_of_error or
                x_vector[eta.column] < -MAGIC_NUMBERS.margin_of_error then
            local scalar = x_vector[eta.column]
            for j = 1, #x_vector do
                ---@diagnostic disable: need-check-nil
                if j == eta.column then
                    x_vector[j] = scalar * eta.vector[j]
                elseif eta.vector[j] ~= 0 then
                    x_vector[j] = x_vector[j] + scalar * eta.vector[j]
                end
            end
        end
    end

    return x_vector
end


--- Calculate `A = P^T LU Q^T E` (for debugging)
---@return number[][] matrix column-major order square matrix
function LUDecomposition:recompose()
    -- Calculate `PAQ = LU`
    local a_matrix = {}  ---@type number[][]
    
    for j = 1, #self.u_matrix do
        local qj = self.q_vector[j]  ---@as integer
        a_matrix[qj] = {}
        for i = 1, #self.u_matrix do
            local pi = self.p_vector[i]  ---@as integer
            a_matrix[qj][pi] = 0.0
            for k = 1, math.min(i, j) do
                ---@diagnostic disable: need-check-nil
                local pk = self.p_vector[k]  ---@as integer
                a_matrix[qj][pi] = a_matrix[qj][pi] + self.l_matrix[i][k] * self.u_matrix[pk][qj]
            end
        end
    end

    -- Calculate `A* = AE`
    for k = 1, #self.eta_updates do
        local eta_vector = lib.flib.shallow_copy(self.eta_updates[k].vector)
        local column = self.eta_updates[k].column
        local scalar = eta_vector[column]  ---@as number
        for i = 1, #eta_vector do
            if i == column then
                eta_vector[i] = 1 / scalar
            else
                eta_vector[i] = -eta_vector[i] / scalar
            end
        end

        a_matrix[column] = lib.matrix.right_mult_cmo(a_matrix, eta_vector)
    end

    return a_matrix
end


---@param i integer
---@param j integer
---@param min_i integer
---@param min_j integer
---@return integer pivot_row
---@return integer pivot_column
function LUDecomposition:_rook_pivot_vertical(i, j, min_i, min_j)
    ---@diagnostic disable: need-check-nil
    local pi = self.p_vector[i]  ---@as integer
    local qj = self.q_vector[j]  ---@as integer
    local max = self.u_matrix[pi][qj] >= 0 and self.u_matrix[pi][qj] or -self.u_matrix[pi][qj]
    local pivot_row = i
    for k = min_i, #self.u_matrix do
        if k ~= i then
            local pk = self.p_vector[k]  ---@as integer
            local cell_abs = self.u_matrix[pk][qj] >= 0 and self.u_matrix[pk][qj] or -self.u_matrix[pk][qj]
            if cell_abs > max then
                max = cell_abs
                pivot_row = k
            end
        end
    end
    if pivot_row ~= i then
        return self:_rook_pivot_horizontal(pivot_row, j, min_i, min_j)
    end

    return i, j
end


---@param i integer
---@param j integer
---@param min_i integer
---@param min_j integer
---@return integer pivot_row
---@return integer pivot_column
function LUDecomposition:_rook_pivot_horizontal(i, j, min_i, min_j)
    ---@diagnostic disable: need-check-nil
    local pi = self.p_vector[i]  ---@as integer
    local qj = self.q_vector[j]  ---@as integer
    local max = self.u_matrix[pi][qj] >= 0 and self.u_matrix[pi][qj] or -self.u_matrix[pi][qj]
    local pivot_column = j
    for k = min_j, #self.u_matrix[i] do
        if k ~= j then
            local qk = self.q_vector[k]  ---@as integer
            local cell_abs = self.u_matrix[pi][qk] >= 0 and self.u_matrix[pi][qk] or -self.u_matrix[pi][qk]
            if cell_abs > max then
                max = cell_abs
                pivot_column = k
            end
        end
    end
    if pivot_column ~= j then
        return self:_rook_pivot_vertical(i, pivot_column, min_i, min_j)
    end

    return i, j
end


return LUDecomposition

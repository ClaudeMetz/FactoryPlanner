---@class LUDecomposition
---@field u_matrix number[][] `U*` permuted upper triangular matrix where `U = P U*`
---@field l_matrix number[][] `L` lower unit triangular matrix
---@field p_vector integer[] row shift vector representing `P`
---@field q_vector integer[] column shift vector representing `Q`
---@field ft_updates FTUpdate[] array of vectors representing `R_n`
local LUDecomposition = {}
LUDecomposition.__index = LUDecomposition

---@class FTUpdate
---@field vector number[]
---@field index integer


---@param size integer
---@return LUDecomposition
function LUDecomposition:init(size)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        u_matrix = {},
        l_matrix = {},
        p_vector = {},
        q_vector = {},
        ft_updates = {}
    }  ---@type LUDecomposition
    setmetatable(o, self)

    -- Initialize the matrices and the permutation vectors
    for k = 1, size do
        o.p_vector[k] = k
        o.q_vector[k] = k
        o.u_matrix[k] = {}
        o.l_matrix[k] = {}
        for j = 1, size do o.u_matrix[k][j] = 0 end
        for j = 1, k - 1 do o.l_matrix[k][j] = 0 end
        o.u_matrix[k][k] = 1
        o.l_matrix[k][k] = 1
    end

    return o
end


--- Performs LU decomposition `LU = PAQ`
---@param matrix number[][] column-major order square matrix
---@return LUDecomposition?
function LUDecomposition:decompose(matrix)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        u_matrix = {},
        l_matrix = {},
        p_vector = {},
        q_vector = {},
        ft_updates = {}
    }  ---@type LUDecomposition
    setmetatable(o, self)

    -- Initialize the matrices and the permutation vectors
    for i = 1, #matrix do
        o.p_vector[i] = i
        o.q_vector[i] = i
        o.u_matrix[i] = {}
        o.l_matrix[i] = {}
        for j = 1, #matrix do o.u_matrix[i][j] = matrix[j][i] end
    end

    for k = 1, #o.u_matrix - 1 do
        ---@diagnostic disable: need-check-nil
        local qk = o.q_vector[k]  ---@as integer

        -- Find pivot
        local pivot_row = k
        local pivot_col = k
        pivot_row, pivot_col = o:_rook_pivot_vertical(k, k, k, k)

        -- Permute
        if pivot_row ~= k then
            local temp_u = o.u_matrix[pivot_row]
            o.u_matrix[pivot_row] = o.u_matrix[k]
            o.u_matrix[k] = temp_u

            local temp_l = o.l_matrix[pivot_row]
            o.l_matrix[pivot_row] = o.l_matrix[k]
            o.l_matrix[k] = temp_l

            local temp_p = o.p_vector[pivot_row] or 0
            o.p_vector[pivot_row] = o.p_vector[k]  ---@as integer
            o.p_vector[k] = temp_p
        end
        if pivot_col ~= k then
            qk = o.q_vector[pivot_col] or 0
            o.q_vector[pivot_col] = o.q_vector[k]  ---@as integer
            o.q_vector[k] = qk
        end

        if o.u_matrix[k][qk] ~= 0 then
            -- Row-subtract below the pivot
            for i = k + 1, #o.u_matrix do
                local scalar = o.u_matrix[i][qk] / o.u_matrix[k][qk]
                o.u_matrix[i][qk] = 0
                o.l_matrix[i][k] = scalar
                if scalar ~= 0 then
                    for j = k + 1, #o.u_matrix do
                        local qj = o.q_vector[j]  ---@as integer
                        o.u_matrix[i][qj] = o.u_matrix[i][qj] - scalar * o.u_matrix[k][qj]
                    end
                end
            end
        else
            -- Basis is unfeasible
            return nil
        end
    end

    -- Fill the diagonal of the lower triangular matrix
    for k = 1, #o.l_matrix do o.l_matrix[k][k] = 1 end

    return o
end


--- Updates the decomposed matrix by replacing a column.
--- The updates are stored as Forrest-Tomlin updates
---@param vector number[] `u` where `LR u = P a` and `a` is the column entering the basis
---@param column integer
---@return boolean is_stable
function LUDecomposition:update(vector, column)
    -- Find the update index by reversing the column permutations
    local index = 0
    for j = 1, #self.q_vector do
        if self.q_vector[j] == column then
            index = j
            break
        end
    end
    if index == 0 then return false end

    -- Solve `U^T t = U_rr e_r`
    local t_vector = {}
    t_vector[index] = 1
    for k = index + 1, #self.u_matrix[index] do
        ---@diagnostic disable: need-check-nil
        local qk = self.q_vector[k]
        t_vector[k] = 0.0
        for i = index, k - 1 do
            if  t_vector[i] ~= 0 and self.u_matrix[i][qk] ~= 0 then
                t_vector[k] = t_vector[k] - t_vector[i] * self.u_matrix[i][qk]
            end
        end
        t_vector[k] = t_vector[k] / self.u_matrix[k][qk]
    end

    -- Check for stablility
    for i = index + 1, #self.u_matrix do
        if t_vector[i] > MAGIC_NUMBERS.simplex_update_threshold or
                t_vector[i] < -MAGIC_NUMBERS.simplex_update_threshold then
            return false
        end
    end

    -- Compute new diagonal coefficient
    local delta = 0.0
    for i = index, #self.u_matrix do
        if t_vector[i] ~= 0 and vector[i] ~= 0 then
            delta = delta + t_vector[i] * vector[i]
        end
    end

    -- Update the upper matrix
    for i = 1, #self.u_matrix do self.u_matrix[i][column] = vector[i] end
    for j = index + 1, #self.u_matrix[index] do self.u_matrix[index][self.q_vector[j]--[[@cast -nil]]] = 0 end
    self.u_matrix[index]--[[@cast -nil]][column] = delta

    -- Permute rows
    local temp_u = self.u_matrix[index]
    for i = index, #self.u_matrix - 1 do self.u_matrix[i] = self.u_matrix[i + 1] end
    self.u_matrix[#self.u_matrix] = temp_u

    -- Permute columns
    local temp_q = self.q_vector[index]
    for j = index, #self.q_vector - 1 do self.q_vector[j] = self.q_vector[j + 1] end
    self.q_vector[#self.q_vector] = temp_q

    -- Store the update
    local update = { vector = t_vector, index = index }  ---@type FTUpdate
    table.insert(self.ft_updates, update)

    return true
end


--- Calculates `x` vector where `x^T A = v^T` (`A^T x = v`).
--- After decomposition, the equation becomes `x^T P^T LRU = v^T Q`
---@param vector number[]
---@return number[]
function LUDecomposition:solve_left(vector)
    -- Solve `y^T U = z^T Q`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.u_matrix do
        ---@diagnostic disable: need-check-nil
        local qk = self.q_vector[k]  ---@as integer
        y_vector[k] = vector[qk]
        for i = 1, k - 1 do
            if y_vector[i] ~= 0 and self.u_matrix[i][qk] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.u_matrix[i][qk]
            end
        end
        y_vector[k] = y_vector[k] / self.u_matrix[k][qk]
    end

    -- Solve `y_(n-1)^T R_n = y_n^T`
    -- The coefficients of the `R` matrix are the negations of the update vector
    for k = #self.ft_updates, 1, -1 do
        local update = self.ft_updates[k]

        local temp = y_vector[#y_vector]
        for j = #y_vector, update.index + 1, -1 do y_vector[j] = y_vector[j - 1] end
        y_vector[update.index] = temp

        if y_vector[update.index] ~= 0 then
            for j = update.index + 1, #y_vector do
                if update.vector[j] ~= 0 then
                    ---@diagnostic disable: need-check-nil
                    y_vector[j] = y_vector[j] + y_vector[update.index] * update.vector[j]
                end
            end
        end
    end

    -- Solve `x^T P^T L = y^T`
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
--- After decomposition, the equation becomes `LRU Q^T x = P v`
---@param vector number[]
---@return number[] `x`
---@return number[] `u` update vector for which `LR u = P a`
function LUDecomposition:solve_right(vector)
    -- Solve `L y = P v`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.l_matrix do
        y_vector[k] = vector[self.p_vector[k]--[[@cast -nil]]]
        for j = 1, k - 1 do
            if  y_vector[j] ~= 0 and self.l_matrix[k][j] ~= 0 then
                ---@diagnostic disable: need-check-nil
                y_vector[k] = y_vector[k] - y_vector[j] * self.l_matrix[k][j]
            end
        end
    end

    -- Solve `R_n y_n = y_(n-1)`
    -- The coefficients of the `R` matrix are the negations of the update vector
    for k = 1, #self.ft_updates do
        local update = self.ft_updates[k]
        for j = update.index + 1, #y_vector do
            if y_vector[j] ~= 0 and update.vector[j] ~= 0 then
                ---@diagnostic disable: need-check-nil
                y_vector[update.index] = y_vector[update.index] + y_vector[j] * update.vector[j]
            end
        end

        local temp = y_vector[update.index]
        for j = update.index, #y_vector - 1 do y_vector[j] = y_vector[j + 1] end
        y_vector[#y_vector] = temp
    end

    -- Solve `U Q^T x = u`
    local x_vector = {}  ---@type number[]
    for k = #self.u_matrix, 1, -1 do
        ---@diagnostic disable: need-check-nil
        local qk = self.q_vector[k]  ---@as integer
        local cell = y_vector[k]
        for j = k + 1, #self.u_matrix do
            local qj = self.q_vector[j]  ---@as integer
            if x_vector[qj] ~= 0 and self.u_matrix[k][qj] ~= 0 then
                cell = cell - x_vector[qj] * self.u_matrix[k][qj]
            end
        end
        x_vector[qk] = cell / self.u_matrix[k][qk]
    end

    return x_vector, y_vector
end


--- Calculate `A = P^T LRU Q^T` (for debugging)
---@return number[][] matrix column-major order square matrix
function LUDecomposition:recompose()
    local u_matrix = lib.flib.deep_copy(self.u_matrix)
    local q_vector = lib.flib.deep_copy(self.q_vector)

    -- Calculate `U* = RU`
    for k = #self.ft_updates, 1, -1 do
        local update = self.ft_updates[k]

        -- Permute rows
        local temp_u = u_matrix[#u_matrix]
        for i = #u_matrix - 1, update.index, -1 do u_matrix[i + 1] = u_matrix[i] end
        u_matrix[update.index] = temp_u

        -- Permute columns
        local temp_q = q_vector[#q_vector]
        for j = #q_vector - 1, update.index, -1 do q_vector[j + 1] = q_vector[j] end
        q_vector[update.index] = temp_q

        -- Update the upper matrix
        -- The coefficients of the `R` matrix are the negations of the update vector
        for j = update.index, #u_matrix[update.index] do
            local qj = q_vector[j]  ---@as integer
            local cell = u_matrix[update.index][qj]
            for i = update.index + 1, #u_matrix do
                ---@diagnostic disable: need-check-nil
                cell = cell - update.vector[i] * u_matrix[i][qj]
            end
            u_matrix[update.index][qj] = cell
        end
    end

    -- Calculate `PAQ = LU*`
    local a_matrix = {}  ---@type number[][]
    
    for j = 1, #u_matrix do
        local qj = q_vector[j]  ---@as integer
        a_matrix[qj] = {}
        for i = 1, #u_matrix do
            local pi = self.p_vector[i]  ---@as integer
            a_matrix[qj][pi] = 0.0
            for k = 1, i do
                ---@diagnostic disable: need-check-nil
                a_matrix[qj][pi] = a_matrix[qj][pi] + self.l_matrix[i][k] * u_matrix[k][qj]
            end
        end
    end

    return a_matrix
end


--- Get permuted upper matrix `U` (for debugging)
---@return number[][]
function LUDecomposition:get_upper_matrix()
    local result = {}  ---@type number[][]
    for i = 1, #self.u_matrix do
        result[i] = {}
        for j = 1, #self.u_matrix[i] do
            local qj = self.q_vector[j]  ---@as integer
            result[i][j] = self.u_matrix[i][qj]
        end
    end
    return result
end


---@param i integer
---@param j integer
---@param min_i integer
---@param min_j integer
---@return integer pivot_row
---@return integer pivot_column
function LUDecomposition:_rook_pivot_vertical(i, j, min_i, min_j)
    ---@diagnostic disable: need-check-nil
    local qj = self.q_vector[j]  ---@as integer
    local max = self.u_matrix[i][qj] >= 0 and self.u_matrix[i][qj] or -self.u_matrix[i][qj]
    local pivot_row = i
    for k = min_i, #self.u_matrix do
        if k ~= i then
            local cell_abs = self.u_matrix[k][qj] >= 0 and self.u_matrix[k][qj] or -self.u_matrix[k][qj]
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
    local qj = self.q_vector[j]  ---@as integer
    local max = self.u_matrix[i][qj] >= 0 and self.u_matrix[i][qj] or -self.u_matrix[i][qj]
    local pivot_column = j
    for k = min_j, #self.u_matrix[i] do
        if k ~= j then
            local qk = self.q_vector[k]  ---@as integer
            local cell_abs = self.u_matrix[i][qk] >= 0 and self.u_matrix[i][qk] or -self.u_matrix[i][qk]
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

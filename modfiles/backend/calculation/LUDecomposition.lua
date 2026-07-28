---@class LUDecomposition
---@field u_matrix number[][] `U*` permuted upper triangular matrix where `U = P U*`
---@field l_matrix number[][] `L` lower unit triangular matrix
---@field p_vector integer[] row shift vector representing `P`
---@field eta_updates EtaUpdate[] array of vectors representing `E_n^-1`
local LUDecomposition = {}
LUDecomposition.__index = LUDecomposition

---@class EtaUpdate
---@field vector number[]
---@field column integer


--- Performs LU decomposition `L U = P A`
---@param matrix number[][] column-major order square matrix
---@return LUDecomposition
function LUDecomposition:init(matrix)
    ---@diagnostic disable-next-line: missing-fields
    local o = {
        u_matrix = {},
        l_matrix = {},
        p_vector = {},
        p_transposed = {},
        eta_updates = {}
    }  ---@type LUDecomposition
    setmetatable(o, self)

    -- Initialize the matrices and the permutation vectors
    for i = 1, #matrix do
        o.p_vector[i] = i
        o.u_matrix[i] = {}
        o.l_matrix[i] = {}
        for j = 1, #matrix do o.u_matrix[i][j] = matrix[j][i] end
        for j = 1, #matrix do o.l_matrix[i][j] = 0 end
    end

    for k = 1, #o.u_matrix - 1 do
        ---@diagnostic disable: need-check-nil
        local pk = o.p_vector[k]  ---@as integer

        -- Find pivot
        local pivot_row = k
        local max = o.u_matrix[pk][k] > 0 and o.u_matrix[pk][k] or -o.u_matrix[pk][k]
        for i = k + 1, #o.u_matrix do
            local pi = o.p_vector[i]  ---@as integer
            local cell = o.u_matrix[pi][k] > 0 and o.u_matrix[pi][k] or -o.u_matrix[pi][k]
            if cell > max then
                max = cell
                pivot_row = i
            end
        end

        if max > 0 then
            -- Permute
            if pivot_row ~= k then
                local temp_l = o.l_matrix[pivot_row]
                o.l_matrix[pivot_row] = o.l_matrix[k]
                o.l_matrix[k] = temp_l

                pk = o.p_vector[pivot_row] or 0
                o.p_vector[pivot_row] = o.p_vector[k]  ---@as integer
                o.p_vector[k] = pk
            end

            -- Row-subtract below the pivot
            for i = k + 1, #o.u_matrix do
                local pi = o.p_vector[i]  ---@as integer
                local scalar = o.u_matrix[pi][k] / o.u_matrix[pk][k]
                o.u_matrix[pi][k] = 0
                o.l_matrix[i][k] = scalar
                if scalar ~= 0 then
                    for j = k + 1, #o.u_matrix do
                        o.u_matrix[pi][j] = o.u_matrix[pi][j] - scalar * o.u_matrix[pk][j]
                    end
                end
            end
        else
            -- Column vector is degenerate. Just put a big number here and hope nothing goes wrong
            o.u_matrix[pk][k] = 1e100
        end
    end

    -- Fill the diagonal of the lower triangular matrix
    for k = 1, #o.l_matrix do o.l_matrix[k][k] = 1 end

    return o
end


--- Updates the decomposed matrix by replacing a column.
--- The updates are stored as eta factorizations
---@param vector number[] `v` where `LUE v` is the new column
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
--- After decomposition, the equation becomes `(P x)^T LUE = v^T`
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

    -- Solve `y^T U = z^T`
    local y_vector = {}  ---@type number[]
    for k = 1, #self.u_matrix do
        ---@diagnostic disable: need-check-nil
        local pk = self.p_vector[k]  ---@as integer
        y_vector[k] = z_vector[k]
        for i = 1, k - 1 do
            local pi = self.p_vector[i]  ---@as integer
            if y_vector[i] ~= 0 and self.u_matrix[pi][k] ~= 0 then
                y_vector[k] = y_vector[k] - y_vector[i] * self.u_matrix[pi][k]
            end
        end
        y_vector[k] = y_vector[k] / self.u_matrix[pk][k]
    end

    -- Solve `(P x)^T L = y^T`
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
--- After decomposition, the equation becomes `LUE x = P v`
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

    -- Solve `U x = y`
    local x_vector = {}  ---@type number[]
    for k = #self.u_matrix, 1, -1 do
        ---@diagnostic disable: need-check-nil
        local pk = self.p_vector[k]  ---@as integer
        local cell = y_vector[k]
        for i = k + 1, #self.u_matrix do
            if x_vector[i] ~= 0 and self.u_matrix[pk][i] ~= 0 then
                cell = cell - x_vector[i] * self.u_matrix[pk][i]
            end
        end
        x_vector[k] = cell / self.u_matrix[pk][k]
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


--- Perform `A = P^T LUE` (for debugging)
---@return number[][] matrix column-major order square matrix
function LUDecomposition:recompose()
    -- Calculate `PA = LU`
    local a_matrix = {}  ---@type number[][]
    
    for j = 1, #self.u_matrix do
        a_matrix[j] = {}
        for i = 1, #self.u_matrix do
            local pi = self.p_vector[i]  ---@as integer
            a_matrix[j][pi] = 0.0
            for k = 1, j do
                ---@diagnostic disable: need-check-nil
                local pk = self.p_vector[k]  ---@as integer
                if k <= i then
                    a_matrix[j][pi] = a_matrix[j][pi] + self.l_matrix[i][k] * self.u_matrix[pk][j]
                end
            end
        end
    end

    -- Calculate `R* = RE`
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


return LUDecomposition

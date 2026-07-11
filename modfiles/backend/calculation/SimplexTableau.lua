---@namespace Simplex


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"

---@class SimplexTableau
---@field _matrix number[][]
---@field _rows table<string, integer> constraints
---@field _cols table<string, integer> variables
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau


---@return SimplexTableau
function SimplexTableau:init()
    local instance = {
        _matrix = {{0}},
        _rows = {objective = 1},
        _cols = {solution = 1}
    }

    setmetatable(instance, self)
    ---@cast instance SimplexTableau
    return instance
end


--- Adds a column representing the line recipe.
--- Missing items are automatically added.
---@param line_data LineData
function SimplexTableau:add_line_variable(line_data)
    local line_key = "line_" .. line_data.line_id

    -- Line is already present in the tableau
    if self._cols[line_key] then return end

    local col_index = self:_add_column(line_key)

    ---@param items ItemList
    ---@param sign 1 | -1
    local function add_rows(items, sign)
        for item, value in pairs(items) do
            local item_row_key = "item_" .. item
            local row_index = 0

            -- Add the item to the tableau if not already present
            if not self._rows[item_row_key] then
                row_index = self:_add_row(item_row_key)
            else
                row_index = self._rows[item_row_key]
            end

            local x = self._matrix[row_index]--[[@cast -nil]][col_index] or 0
            self._matrix[row_index]--[[@cast -nil]][col_index] = x + sign * value
        end
    end

    -- Populate the tableau matrix with the line results
    add_rows(line_data.products, 1)
    add_rows(line_data.ingredients, -1)
end


--- Adds a slack variable to the inequality constraint of the given item
---@param key PrototypeName
---@param direction ItemDirection
---@param score number?
function SimplexTableau:add_item_variable(key, direction, score)
    score = score or 0
    local item_row_key = "item_" .. key
    local item_col_key = "item_" .. direction .. "_" .. key

    -- This is opposite to recipe where products > 0 and ingredients < 0
    local sign = (direction == "in" and 1) or (direction == "out" and -1) or 0
    if sign == 0 then return end

    -- Item variable is already present in the tableau
    if self._cols[item_col_key] then return end

    -- Check that the item constraint is present in the tableau
    local row_index = self._rows[item_row_key] or 0
    if not self._matrix[row_index] then return end

    -- Fill the table values
    local col_index = self:_add_column(item_col_key, score)
    self._matrix[row_index][col_index] = sign
end


--- Adds an additional constraint to a given item
---@param key PrototypeName
---@param direction ItemDirection
---@param limit number
---@param type InequalityType
---@param score number?
function SimplexTableau:add_item_constraint(key, direction, type, limit, score)
    score = score or 0
    local item_col_key = "item_" .. direction .. "_" .. key

    -- Check that the item variable is present in the tableau
    local item_col_index = self._cols[item_col_key] or 0
    if item_col_index == 0 then return end

    -- Add a new row for the constaint.
    local row_index = self:_add_row("c_" .. #self._matrix + 1)

    -- Fill the row values
    self._matrix[row_index]--[[@cast -nil]][item_col_index] = 1
    self._matrix[row_index]--[[@cast -nil]][1] = limit

    -- Update the item variable score
    local x = self._matrix[1]--[[@cast -nil]][item_col_index] or 0
    self._matrix[1]--[[@cast -nil]][item_col_index] = x - score  -- score coefficient is opposite

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column("s_" .. #self._matrix[1] + 1)

    -- Fill the inequality between the item varable and the slack
    local sign = (type == "<=" and 1) or (type == ">=" and -1) or 0
    self._matrix[row_index]--[[@cast -nil]][slack_col_index] = sign
end


---@param vv_score number virtual variable score (actually cost, since it should be negative)
function SimplexTableau:solve(vv_score)
    -- Only allow non-negative limits (should never happen in practice though)
    for i = 2, #self._matrix do
        if self._matrix[i][1] < 0 then lib.matrix.row_mult(self._matrix, i, -1) end
    end

    -- Find basic variables (column where one row is 1 and the rest are 0)
    -- We don't need to be very precise regarding floating point errors. This is just an optimization
    local basic = {}  ---@type string[]
    for j = 2, #self._matrix[1] do
        local one_index = nil  ---@type integer?
        local is_basic = true
        for i = 2, #self._matrix do
            if self._matrix[i][j] ~= 0 then
                if self._matrix[i][j] ~= 1 then
                    is_basic = false
                    break
                elseif one_index then
                    is_basic = false
                    break
                else
                    one_index = i
                end
            end
        end

        if is_basic and one_index then
            for k, v in pairs(self._cols) do
                if j == v then
                    basic[one_index] = k
                    break
                end
            end
        end
    end

    -- Add a virtual variable with a very large cost for each non-basic row
    for i = 2, #self._matrix do
        if not basic[i] then
            local virtual_key = "y_" .. i
            local col_index = self:_add_column(virtual_key, vv_score)
            self._matrix[i][col_index] = 1
            basic[i] = virtual_key
        end
    end

    -- Reduce the score function of the basic variables to 0
    for i = 2, #self._matrix do
        local col_index = self._cols[basic[i]] or 0
        local pivot = self._matrix[1]--[[@cast -nil]][col_index] or 0
        if pivot ~= 0 then
            lib.matrix.row_subtract(self._matrix, 1, i, pivot)
        end
    end

    ---@return boolean done
    ---@return SolverState state
    local function solve_step()
        -- Select the variable with the most negative score as input
        local col_index = 0
        local min = 0.0
        for i = 2, #self._matrix[1] do
            if self._matrix[1][i] < min then
                col_index = i
                min = self._matrix[1][i]
            end
        end

        if col_index == 0 then
            -- We are done, but check that we actually have a solution
            ---@TODO
            return true, "solved"
        end

        -- Select the basis with the smallest ratio
        local row_index = 0
        min = 2.0^1023
        for i = 2, #self._matrix do
            local denominator = self._matrix[i][col_index] or 0
            local ratio = (denominator > 0 and self._matrix[i][1]) and (self._matrix[i][1] / denominator) or 0
            if ratio > 0 and ratio < min then
                row_index = i
                min = ratio
            end
        end

        if col_index == 0 then return true, "unbounded" end

        return false, "in-progress"
    end

    -- Iterate solving steps
    local done = false
    local state = "in-progress"  ---@type SolverState
    -- repeat
    --     done, state = solve_step()
    -- until done
end


---@param key string
---@param limit number?
---@return integer index
function SimplexTableau:_add_row(key, limit)
    local row_index = #self._matrix + 1
    self._rows[key] = row_index
    self._matrix[row_index] = {}

    -- Populate the row
    self._matrix[row_index]--[[@cast -nil]][1] = limit or 0
    for i = 2, #self._matrix[1] do
        self._matrix[row_index][i] = 0
    end

    return row_index
end


---@private
---@param key string
---@param score number?
---@return integer index
function SimplexTableau:_add_column(key, score)
    score = score or 0
    local col_index = #self._matrix[1] + 1
    self._cols[key] = col_index

    -- Populate the column
    self._matrix[1]--[[@cast -nil]][col_index] = -score  -- score coefficient is opposite
    for i = 2, #self._matrix do
        self._matrix[i][col_index] = 0
    end

    return col_index
end


return SimplexTableau

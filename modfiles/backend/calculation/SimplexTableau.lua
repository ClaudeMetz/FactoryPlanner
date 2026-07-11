---@namespace Simplex


---@alias InequalityType "==" | "<=" | ">="

---@class SimplexTableau
---@field _matrix number[][]
---@field _rows table<string, integer> constraints
---@field _cols table<string, integer> variables
---@field _signs table<string, 1 | -1> variable signs
---@field _types InequalityType[]
---@field _free_rows integer
---@field _slacks integer item variables are also slacks, but we don't count them
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau


---@return SimplexTableau
function SimplexTableau:init()
    local instance = {
        _matrix = {{0}},
        _rows = {objective = 1},
        _cols = {solution = 1},
        _types = {"=="},
        _signs = {},
        _free_rows = 0,
        _slacks = 0
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
            local item_key = "item_" .. item
            local row_index = 0

            -- Add the item to the tableau if not already present
            if not self._rows[item_key] then
                row_index = self:_add_row(item_key)
            else
                row_index = self._rows[item_key]
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
---@param type InequalityType
---@param score number?
function SimplexTableau:add_item_variable(key, type, score)
    score = score or 0

    local item_key = "item_" .. key

    -- Item variable is already present in the tableau
    if self._cols[item_key] then return end

    -- Not an inequality
    local sign = (type == ">=" and 1) or (type == "<=" and -1) or 0
    if sign == 0 then return end

    -- Check that the item constraint is present in the tableau
    local row_index = self._rows[item_key] or 0
    if not self._matrix[row_index] then return end

    -- Fill the table values
    local col_index = self:_add_column(item_key, -score, sign) -- score coefficient is opposite
    self._matrix[row_index][col_index] = -sign  -- slack coefficient is opposite
    self._types[row_index] = type
end


--- Adds an additional constraint to a given item
---@param key PrototypeName
---@param bound number the constraint limit
---@param type InequalityType
---@param score number?
function SimplexTableau:add_item_constraint(key, bound, type, score)
    score = score or 0

    local item_key = "item_" .. key

    -- Check that the item variable is present in the tableau
    local item_col_index = self._cols[item_key] or 0
    if item_col_index == 0 then return end

    -- Add a new row for the constaint.
    self._free_rows = self._free_rows + 1
    local row_index = self:_add_row("c_" .. self._free_rows, 0, type)

    if type == "==" then
        -- For equality, just set the score and the bound
        local x = self._matrix[1]--[[@cast -nil]][item_col_index] or 0
        self._matrix[row_index]--[[@cast -nil]][1] = bound
        self._matrix[row_index]--[[@cast -nil]][item_col_index] = self._signs[item_key]
        self._matrix[1]--[[@cast -nil]][item_col_index] = x - score  -- score coefficient is opposite
    else
        local sign = (type == ">=" and 1) or (type == "<=" and -1) or 0
        if sign == 0 then return end  -- sanity check

        -- Add a new slack variable for the inequality
        self._slacks = self._slacks + 1
        local slack_key = "s_" .. self._slacks
        local slack_col_index = self:_add_column(slack_key)

        -- Fill the inequality between the item varable and the slack
        self._matrix[row_index]--[[@cast -nil]][item_col_index] = self._signs[item_key]
        self._matrix[row_index]--[[@cast -nil]][slack_col_index] = -type  -- slack coefficient is opposite
        self._matrix[row_index]--[[@cast -nil]][1] = bound

        -- Update the item variable score
        local x = self._matrix[1]--[[@cast -nil]][item_col_index] or 0
        self._matrix[1]--[[@cast -nil]][item_col_index] = x - score  -- score coefficient is opposite
    end
end


---@param vv_score number virtual variable score (cost, since it should be negative)
function SimplexTableau:solve(vv_score)
    -- Add a virtual variable with a very large cost for each row to for a basic feasible solution
    local basis = {}  ---@type string[]
    for i = 2, #self._matrix do
        local virtual_key = "y_" .. i - 1
        local col_index = self:_add_column(virtual_key, vv_score)
        self._matrix[i][col_index] = 1
        basis[i] = virtual_key
    end

    -- Reduce the score function of the bases to 0
    for i = 2, #self._matrix do
        local col_index = self._cols[basis[i]] or 0
        local pivot = self._matrix[1]--[[@cast -nil]][col_index] or 0
        if pivot ~= 0 then
            lib.matrix.row_subtract(self._matrix, 1, i, pivot)
        end
    end

    -- Iterate solving steps
    local done = false
    repeat
        done = self:_solve_step()
    until done
end


---@param key string
---@param bound number?
---@param type InequalityType?
---@return integer index
function SimplexTableau:_add_row(key, bound, type)
    local row_index = #self._matrix + 1
    self._rows[key] = row_index
    self._matrix[row_index] = {}

    -- Populate the row
    self._matrix[row_index]--[[@cast -nil]][1] = bound or 0
    for i = 2, #self._matrix[1] do
        self._matrix[row_index][i] = 0
    end
    self._types[row_index] = type or "=="

    return row_index
end


---@private
---@param key string
---@param score number?
---@param sign (1 | -1)?
---@return integer index
function SimplexTableau:_add_column(key, score, sign)
    sign = sign or 1  -- default to positive variable
    local col_index = #self._matrix[1] + 1
    self._cols[key] = col_index
    self._signs[key] = sign

    -- Populate the column
    self._matrix[1]--[[@cast -nil]][col_index] = score and -score or 0  -- score coefficient is opposite
    for i = 2, #self._matrix do
        self._matrix[i][col_index] = 0
    end

    return col_index
end


---@return boolean done
function SimplexTableau:_solve_step()
    -- Select the variable with the most negative score as input
    local col_index = 0
    local min = 0.0
    for i = 2, #self._matrix[1] do
        if self._matrix[1][i] < min then
            col_index = i
            min = self._matrix[1][i]
        end
    end

    if col_index == 0 then return true end

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

    return false
end


return SimplexTableau

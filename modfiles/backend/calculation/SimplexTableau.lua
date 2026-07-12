---@namespace Simplex


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"
---@alias FloorResultTable table<ObjectID, FloorResult>
---@alias LineResultTable table<ObjectID, LineResult>

---@class SimplexTableau
---@field _matrix number[][]
---@field _rows table<string, integer> constraints
---@field _cols table<string, integer> variables
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau

---@class FloorResult
---@field floor_id ObjectID
---@field state SolverState?
---@field objective number?
---@field products ItemList
---@field ingredients ItemList
---@field line_results LineResultTable

---@class LineResult
---@field line_id ObjectID
---@field machine_amount number


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
---@param objective number?
function SimplexTableau:add_item_variable(key, direction, objective)
    objective = objective or 0
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
    local col_index = self:_add_column(item_col_key, objective)
    self._matrix[row_index][col_index] = sign
end


--- Adds an additional constraint to a given item
---@param key PrototypeName
---@param direction ItemDirection
---@param limit number
---@param type InequalityType
---@param objective number?
function SimplexTableau:add_item_constraint(key, direction, type, limit, objective)
    objective = objective or 0
    local item_col_key = "item_" .. direction .. "_" .. key

    -- Check that the item variable is present in the tableau
    local item_col_index = self._cols[item_col_key] or 0
    if item_col_index == 0 then return end

    -- Add a new row for the constaint.
    local row_index = self:_add_row("c_" .. #self._matrix + 1)

    -- Fill the row values
    self._matrix[row_index]--[[@cast -nil]][item_col_index] = 1
    self._matrix[row_index]--[[@cast -nil]][1] = limit

    -- Update the item variable objective
    local x = self._matrix[1]--[[@cast -nil]][item_col_index] or 0
    self._matrix[1]--[[@cast -nil]][item_col_index] = x - objective  -- objective coefficient is opposite

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column("s_" .. #self._matrix[1] + 1)

    -- Fill the inequality between the item varable and the slack
    local sign = (type == "<=" and 1) or (type == ">=" and -1) or 0
    self._matrix[row_index]--[[@cast -nil]][slack_col_index] = sign
end


---@param floor_id ObjectID
---@return FloorResult result
function SimplexTableau:solve(floor_id)
    local result = {
        floor_id = floor_id,
        state = "in-progress",
        objective = 0,
        products = {},
        ingredients = {},
        line_results = {}
    }  ---@type FloorResult

    -- Only allow non-negative limits (should never happen in practice though)
    for i = 2, #self._matrix do
        if self._matrix[i][1] < 0 then lib.matrix.row_mult(self._matrix, i, -1) end
    end

    -- Find basic variables (column where one row is 1 and the rest are 0)
    local basic = {}  ---@type string[]
    for j = 2, #self._matrix[1] do
        local one_index = nil  ---@type integer?
        local is_basic = true
        for i = 2, #self._matrix do
            if self._matrix[i][j] > 0.0 + MAGIC_NUMBERS.double_margin_of_error or
                    self._matrix[i][j] < 0.0 - MAGIC_NUMBERS.double_margin_of_error then
                if self._matrix[i][j] > 1.0 + MAGIC_NUMBERS.double_margin_of_error or
                    self._matrix[i][j] < 1.0 - MAGIC_NUMBERS.double_margin_of_error then
                    is_basic = false
                    break
                elseif one_index then
                    is_basic = false
                    break
                else
                    one_index = i
                    self._matrix[i][j] = 1  -- improve precision
                end
            else
                self._matrix[i][j] = 0  -- improve precision
            end
        end

        if is_basic and one_index then
            basic[one_index] = lib.table.find(self._cols, j)
        end
    end

    -- Save the objective function
    local original_objective = self._matrix[1]
    self._matrix[1] = {}
    for j = 1, #original_objective do self._matrix[1][j] = 0 end

    -- Add a virtual variables with negative cost for each non-basic row
    for i = 2, #self._matrix do
        if not basic[i] then
            local virtual_key = "y_" .. #self._matrix[1] + 1
            local col_index = self:_add_column(virtual_key, -1)
            self._matrix[i][col_index] = 1
            basic[i] = virtual_key
        end
    end

    -- Reduce the objective function of the basic variables to 0
    local function reduce_objective()
        for i = 2, #self._matrix do
            local col_index = self._cols[basic[i]] or 0
            local objective = self._matrix[1]--[[@cast -nil]][col_index] or 0
            if objective ~= 0 then
                lib.matrix.row_subtract(self._matrix, 1, i, objective)
            end
        end
    end

    ---@param phase 1 | 2
    ---@return boolean done
    ---@return SolverState state
    local function solve_step(phase)
        -- Select the variable with the most negative objective as the entering variable
        local col_index = 0
        local min = 0.0 - MAGIC_NUMBERS.double_margin_of_error
        for j = 2, #self._matrix[1] do
            if self._matrix[1][j] < min then
                col_index = j
                min = self._matrix[1][j]
            end
        end

        if col_index == 0 then
            -- We are done, but check that we don't have virtual variables in the solution
            if phase == 1 then
                for i = 2, #self._matrix do
                    if basic[i] and string.sub(basic[i], 1, 2) == "y_" then
                        return true, "no-solution"
                    end
                end
            end
            return true, "solved"
        end

        -- Select the basis with the smallest ratio as the leaving variable
        local row_index = 0
        min = 2.0^1023
        for i = 2, #self._matrix do
            local denominator = self._matrix[i][col_index] or 0
            local ratio = (denominator > 0.0 + MAGIC_NUMBERS.double_margin_of_error and self._matrix[i][1])
                    and (self._matrix[i][1] / denominator) or -1
            if ratio >= 0 and ratio < min then
                row_index = i
                min = ratio
            end
            if ratio == 0 then break end
        end

        if row_index == 0 then return true, "unbounded" end

        -- Perform a pivot, swaping the basic variable
        lib.matrix.pivot(self._matrix, row_index, col_index)
        basic[row_index] = lib.table.find(self._cols, col_index)

        return false, "in-progress"
    end

    -- Phase 1: Eliminate the virtual variables
    local done = false
    local max_iterations = 10 * #self._matrix[1]
    reduce_objective()
    repeat
        done, result.state = solve_step(1)
        max_iterations = max_iterations - 1
    until done or max_iterations == 0
    if result.state ~= "solved" then return result end
    result.state = "in-progress"

    -- Remove the virtual variables from the tableau, and restore the objective function
    local start = #original_objective + 1
    local finish = #self._matrix[1]
    self._matrix[1] = original_objective
    for j = start, finish do
        for i = 2, #self._matrix do
            self._matrix[i][j] = nil
        end
        self._cols["y_" .. j] = nil
    end

    -- Phase 2: Find the optimal solution
    done = false
    max_iterations = 10 * #self._matrix[1]
    reduce_objective()
    repeat
        done, result.state = solve_step(2)
        max_iterations = max_iterations - 1
    until done or max_iterations == 0
    if result.state ~= "solved" then return result end

    -- Interpret the result
    result.objective = self._matrix[1]--[[@cast -nil]][1]
    for row, key in pairs(basic) do
        local value = self._matrix[row]--[[@cast -nil]][1] or 0

        -- Ignore zeroes
        if value > 0.0 + MAGIC_NUMBERS.double_margin_of_error or
                value < 0.0 - MAGIC_NUMBERS.double_margin_of_error then
            if string.sub(key, 1, 5) == "line_" then
                local id = tonumber(string.sub(key, 6))
                if id then
                    result.line_results[id] = {
                        line_id = id,
                        machine_amount = value
                    }
                end
            elseif string.sub(key, 1, 9) == "item_out_" then
                local item_key = string.sub(key, 10)
                result.products[item_key] = value
            elseif string.sub(key, 1, 8) == "item_in_" then
                local item_key = string.sub(key, 9)
                result.ingredients[item_key] = value
            end
        end
    end

    return result
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
    for j = 2, #self._matrix[1] do
        self._matrix[row_index][j] = 0
    end

    return row_index
end


---@private
---@param key string
---@param objective number?
---@return integer index
function SimplexTableau:_add_column(key, objective)
    objective = objective or 0
    local col_index = #self._matrix[1] + 1
    self._cols[key] = col_index

    -- Populate the column
    self._matrix[1]--[[@cast -nil]][col_index] = -objective  -- objective coefficient is opposite
    for i = 2, #self._matrix do
        self._matrix[i][col_index] = 0
    end

    return col_index
end


return SimplexTableau

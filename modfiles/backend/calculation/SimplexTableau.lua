---@namespace Simplex


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"
---@alias ConstraintKey "objective" | string `"item_<floor_id>_<proto-key>"` | `"c_<n>"`
---@alias VariableKey "solution" | string `"line_<line_id>"` | `"item_<floor_id>_<in|out>_<proto-key>"` | `"s_<n>"` | `"y_<n>"`
---@alias LineResultTable table<ObjectID, LineResult>
---@alias FloorResultTable table<ObjectID, FloorResult>

---@class SimplexTableau
---@field _matrix number[][]
---@field _rows table<ConstraintKey, integer> constraints
---@field _cols table<VariableKey, integer> variables
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau

---@class SimplexResult
---@field state SolverState?
---@field objective number?
---@field line_results LineResultTable
---@field floor_results FloorResultTable

---@class LineResult
---@field line_id ObjectID
---@field machine_amount number

---@class FloorResult
---@field floor_id ObjectID
---@field products ItemList
---@field ingredients ItemList


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
            if value > 0 then
                local item_row_key = "item_" .. line_data.floor_id .. "_" .. item
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
    end

    -- Populate the tableau matrix with the line results
    add_rows(line_data.products, 1)
    add_rows(line_data.ingredients, -1)
end


--- Adds a slack variable to the inequality constraint of the given item
---@param item PrototypeKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@param objective number?
function SimplexTableau:add_item_variable(item, floor_id, direction, objective)
    local item_row_key = "item_" .. floor_id .. "_" .. item
    local item_col_key = "item_" .. floor_id .. "_".. direction .. "_" .. item

    -- This is opposite to recipes where products > 0 and ingredients < 0
    local sign = (direction == "in" and 1) or (direction == "out" and -1) or 0
    if sign == 0 then return end

    -- Item variable is already present in the tableau
    if self._cols[item_col_key] then return end

    -- Check if the item constraint is present in the tableau
    local row_index = self._rows[item_row_key] or 0
    if not self._matrix[row_index] then
        -- Item not present in this floor (only used in subfloor)
        row_index = self:_add_row(item_row_key)
    end

    -- Fill the table values
    if self._matrix[row_index] then
    local col_index = self:_add_column(item_col_key, objective)
    self._matrix[row_index][col_index] = sign
    end
end


--- Adds an additional constraint to a given item
---@param item PrototypeKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@param type InequalityType
---@param limit number
---@param objective number?
function SimplexTableau:add_item_constraint(item, floor_id, direction, type, limit, objective)
    return self:_add_constraint("item_" .. floor_id .. "_".. direction .. "_" .. item, type, limit, objective)
end


--- Adds an additional constraint to a given line (machine limit)
---@param line_id ObjectID
---@param type InequalityType
---@param limit number
---@param objective number?
function SimplexTableau:add_line_constraint(line_id, type, limit, objective)
    return self:_add_constraint("line_" .. line_id, type, limit, objective)
end


---@param key VariableKey
---@param type InequalityType
---@param limit number
---@param objective number?
function SimplexTableau:_add_constraint(key, type, limit, objective)
    -- Check that the variable is present in the tableau
    local var_col_index = self._cols[key] or 0
    if var_col_index == 0 then return end

    -- Add a new row for the constaint
    local row_index = self:_add_row("c_" .. #self._matrix + 1)

    -- Fill the row values
    self._matrix[row_index]--[[@cast -nil]][var_col_index] = 1
    self._matrix[row_index]--[[@cast -nil]][1] = limit

    -- Update the variable objective
    if objective then
        local x = self._matrix[1]--[[@cast -nil]][var_col_index] or 0
        self._matrix[1]--[[@cast -nil]][var_col_index] = x - objective  -- objective coefficient is opposite
    end

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column("s_" .. #self._matrix[1] + 1)

    -- Fill the inequality between the given variable and the slack variable
    local sign = (type == "<=" and 1) or (type == ">=" and -1) or 0
    self._matrix[row_index]--[[@cast -nil]][slack_col_index] = sign
end


--- Adds a subfloor item variable to the current floor item constraint.
--- In other words, it allows item import/export between the current floor and the subfloor
---@param item PrototypeKey
---@param floor_id ObjectID
---@param direction ItemDirection  from the perspective of the subfloor
---@param objective number?
function SimplexTableau:add_item_transfer(item, floor_id, subfloor_id, direction, objective)
    local item_row_key = "item_" .. floor_id .. "_" .. item
    local item_col_key = "item_" .. subfloor_id .. "_".. direction .. "_" .. item

    local item_row_index = self._rows[item_row_key] or 0
    local item_col_index = self._cols[item_col_key] or 0

    -- Sanity check
    if not self._matrix[item_row_index] or item_col_index == 0 then return end

    -- Update the item variable objective
    if objective then
        local x = self._matrix[1]--[[@cast -nil]][item_col_index] or 0
        self._matrix[1]--[[@cast -nil]][item_col_index] = x - objective  -- objective coefficient is opposite
    end

    -- To the current floor, the subfloor is like a machine
    -- Inputs are ingredients and outputs are products
    self._matrix[item_row_index][item_col_index] = (direction == "in" and -1) or (direction == "out" and 1) or 0
end


--[[
Merges the specified `tableau` (`B`) into self (`A`) The result should be:
```
-------------------
|  0  | o_A | o_B |
-------------------
| s_A |  A* |  0  |
-------------------
| s_B |  0  |  B* |
-------------------
```
where `A*` and `B*` are `A` and `B` without the first row and column
]]--
---@param tableau SimplexTableau
function SimplexTableau:merge(tableau)
    local a_rows, a_cols = #self._matrix, #self._matrix[1]
    local b_rows, b_cols = #tableau._matrix, #tableau._matrix[1]

    -- Copy the solution column
    for i = 2, b_rows do
        self._matrix[a_rows + i - 1] = {}
        self._matrix[a_rows + i - 1][1] = tableau._matrix[i]--[[@cast -nil]][1]
    end

    -- Copy the objective row
    for j = 2, b_cols do
        self._matrix[1]--[[@cast -nil]][a_cols + j - 1] = tableau._matrix[1]--[[@cast -nil]][j]
    end

    -- Fill the top-right section with 0
    for i = 2, a_rows do
        for j = a_cols + 1, a_cols + b_cols - 1 do
            self._matrix[i]--[[@cast -nil]][j] = 0
        end
    end

    -- Fill the bottom-left section with 0
    for i = a_rows + 1, a_rows + b_rows - 1 do
        for j = 2, a_cols do
            self._matrix[i]--[[@cast -nil]][j] = 0
        end
    end

    -- Copy the rest of B into A
    for i = 2, b_rows do
        for j = 2, b_cols do
            self._matrix[a_rows + i - 1]--[[@cast -nil]][a_cols + j - 1] = tableau._matrix[i]--[[@cast -nil]][j]
        end
    end

    -- Copy the row keys
    for k, v in pairs(tableau._rows) do
        if v > 1 then
            local new_row = a_rows + v - 1
            if string.sub(k, 1, 2) == "c_" then
                self._rows["c_" .. new_row] = new_row
            else
                self._rows[k] = new_row
            end
        end
    end

    -- Copy the column keys
    for k, v in pairs(tableau._cols) do
        if v > 1 then
            local new_col = a_cols + v - 1
            -- Don't handle artificial variables
            -- If we tried to merge tableaus after starting solving, we got bigger problems
            if string.sub(k, 1, 2) == "s_" then
                self._cols["s_" .. new_col] = new_col
            else
                self._cols[k] = new_col
            end
        end
    end
end


---@return SimplexResult result
function SimplexTableau:solve()
    local result = {
        state = "in-progress",
        objective = 0,
        products = {},
        ingredients = {},
        line_results = {},
        floor_results = {}
    }  ---@type SimplexResult

    -- Only allow non-negative limits (should never happen in practice though)
    for i = 2, #self._matrix do
        if self._matrix[i][1] < 0 then lib.matrix.row_mult(self._matrix, i, -1) end
    end

    -- Find basic variables (column where one row is 1 and the rest are 0)
    local basic = {}  ---@type VariableKey[]
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
            local col_index = self._cols[basic[i]--[[@cast -nil]]] or 0
            local objective = self._matrix[1]--[[@cast -nil]][col_index] or 0
            if objective ~= 0 then
                lib.matrix.row_subtract(self._matrix, 1, i, objective)
            end
        end
    end

    ---@param phase 1 | 2
    ---@return boolean done
    ---@return SolverState state
    local function pivot_step(phase)
        -- Select the variable with the most negative objective as the entering variable (Danzig's rule)
        -- Add a minimum margin for extra safety
        -- If there is so little score left to maximize, then the solution is pretty close to optimal anyway
        local col_index = 0
        local min = -MAGIC_NUMBERS.margin_of_error
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
            local ratio = (denominator > 0.0 and self._matrix[i][1])
                    and (self._matrix[i][1] / denominator) or -1
            if ratio >= 0 and ratio < min and denominator > MAGIC_NUMBERS.margin_of_error then
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
    local max_iterations = (#self._matrix) ^ 2  -- Upper bound is 2^#v, but average case with random pivots is #c^2
    reduce_objective()
    repeat
        done, result.state = pivot_step(1)
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
    max_iterations = (#self._matrix) ^ 2
    reduce_objective()
    repeat
        done, result.state = pivot_step(2)
        max_iterations = max_iterations - 1
    until done or max_iterations == 0
    if result.state ~= "solved" then return result end

    -- Interpret the result
    result.objective = self._matrix[1]--[[@cast -nil]][1]
    for row, key in pairs(basic) do
        local value = self._matrix[row]--[[@cast -nil]][1] or 0

        -- Ignore zeroes
        if value ~= 0 then
            if string.sub(key, 1, 5) == "line_" then
                local id = tonumber(string.sub(key, 6))
                if id then
                    result.line_results[id] = {
                        line_id = id,
                        machine_amount = value
                    }
                end
            elseif string.sub(key, 1, 5) == "item_" then
                local sep = string.find(key, "_", 6, true) or -2
                local floor_id = tonumber(string.sub(key, 6, sep - 1))  ---@as ObjectID

                -- Create a new floor result if necessary
                if not result.floor_results[floor_id] then
                    result.floor_results[floor_id] = {
                        floor_id = floor_id,
                        products = {},
                        ingredients = {}
                    }  ---@type FloorResult
                end

                if string.sub(key, sep, sep + 4) == "_out_" then
                    local item_key = string.sub(key, sep + 5)
                    result.floor_results[floor_id].products[item_key] = value
                elseif string.sub(key, sep, sep + 3) == "_in_" then
                    local item_key = string.sub(key, sep + 4)
                    result.floor_results[floor_id].ingredients[item_key] = value
                end
            end
        end
    end

    return result
end


---@param key ConstraintKey
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
---@param key VariableKey
---@param objective number?
---@return integer index
function SimplexTableau:_add_column(key, objective)
    local col_index = #self._matrix[1] + 1
    self._cols[key] = col_index

    -- Populate the column
    self._matrix[1]--[[@cast -nil]][col_index] = objective and -objective or 0  -- objective coefficient is opposite
    for i = 2, #self._matrix do
        self._matrix[i][col_index] = 0
    end

    return col_index
end


return SimplexTableau

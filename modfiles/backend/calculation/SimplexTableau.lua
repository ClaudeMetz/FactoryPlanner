---@namespace Simplex
local LUDecomposition = require("backend.calculation.LUDecomposition")


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"
---@alias VariableType "unassigned" | "basic" | "non-basic"
---@alias ConstraintKey string `"item_<floor_id>_<proto-key>"` | `"c_<n>"`
---@alias VariableKey string `"line_<line_id>"` | `"item_<floor_id>_<in|out>_<proto-key>"` | `"s_<n>"` | `"y_<n>"`
---@alias LineResultTable table<ObjectID, LineResult>
---@alias FloorResultTable table<ObjectID, FloorResult>

---@class SimplexTableau
---@field matrix number[][]
---@field objective number[]
---@field solution number[]
---@field rows table<ConstraintKey, integer> constraints
---@field cols table<VariableKey, integer> variables
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau

---@class VariableMap
---@field key VariableKey
---@field type VariableType

---@class SimplexResult
---@field state SolverState?
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
    ---@diagnostic disable-next-line: missing-fields
    local instance = {
        matrix = {},
        objective = {},
        solution = {},
        rows = {},
        cols = {}
    }  ---@type SimplexTableau

    setmetatable(instance, self)
    return instance
end


--- Adds a column representing the line recipe.
--- Missing items are automatically added.
---@param line_data LineData
function SimplexTableau:add_line_variable(line_data)
    local line_key = "line_" .. line_data.line_id

    -- Line is already present in the tableau
    if self.cols[line_key] then return end

    local col_index = self:_add_column(line_key)

    ---@param items ItemList
    ---@param sign 1 | -1
    local function add_rows(items, sign)
        for item, value in pairs(items) do
            if value > 0 then
                local item_row_key = "item_" .. line_data.floor_id .. "_" .. item
                local row_index = 0

                -- Add the item to the tableau if not already present
                if not self.rows[item_row_key] then
                    row_index = self:_add_row(item_row_key)
                else
                    row_index = self.rows[item_row_key]
                end

                ---@diagnostic disable: need-check-nil
                local x = self.matrix[row_index][col_index]
                self.matrix[row_index][col_index] = x + sign * value
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
    if self.cols[item_col_key] then return end

    -- Check if the item constraint is present in the tableau
    local row_index = self.rows[item_row_key] or 0
    if not self.matrix[row_index] then
        -- Item not present in this floor (only used in subfloor)
        row_index = self:_add_row(item_row_key)
    end

    -- Fill the table values
    if self.matrix[row_index] then
    local col_index = self:_add_column(item_col_key, objective)
    self.matrix[row_index][col_index] = sign
    end
end


--- Adds an additional constraint to a given item
---@param item PrototypeKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@param type InequalityType
---@param limit number must be non-negative (`>=0`)
---@param objective number?
function SimplexTableau:add_item_constraint(item, floor_id, direction, type, limit, objective)
    return self:_add_constraint("item_" .. floor_id .. "_".. direction .. "_" .. item, type, limit, objective)
end


--- Adds an additional constraint to a given line (machine limit)
---@param line_id ObjectID
---@param type InequalityType
---@param limit number must be non-negative (`>=0`)
---@param objective number?
function SimplexTableau:add_line_constraint(line_id, type, limit, objective)
    return self:_add_constraint("line_" .. line_id, type, limit, objective)
end


---@param key VariableKey
---@param type InequalityType
---@param limit number must be non-negative (`>=0`)
---@param objective number?
function SimplexTableau:_add_constraint(key, type, limit, objective)
    -- Check that the variable is present in the tableau
    local var_col_index = self.cols[key]
    if not var_col_index then return end
    if limit < 0 then return end

    -- Add a new row for the constaint
    local row_index = self:_add_row("c_" .. #self.matrix + 1)

    -- Fill the row values
    ---@diagnostic disable: need-check-nil
    self.matrix[row_index][var_col_index] = 1
    self.solution[row_index] = limit

    -- Update the variable objective
    if objective then
        local x = self.objective[var_col_index] or 0
        self.objective[var_col_index] = x - objective  -- objective coefficient is opposite
    end

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column("s_" .. #self.matrix[1] + 1)

    -- Fill the inequality between the given variable and the slack variable
    local sign = (type == "<=" and 1) or (type == ">=" and -1) or 0
    self.matrix[row_index][slack_col_index] = sign
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

    local item_row_index = self.rows[item_row_key] or 0
    local item_col_index = self.cols[item_col_key] or 0

    -- Sanity check
    if not self.matrix[item_row_index] or item_col_index == 0 then return end

    -- Update the item variable objective
    if objective then
        local x = self.objective[item_col_index] or 0
        self.objective[item_col_index] = x - objective  -- objective coefficient is opposite
    end

    -- To the current floor, the subfloor is like a machine
    -- Inputs are ingredients and outputs are products
    self.matrix[item_row_index][item_col_index] = (direction == "in" and -1) or (direction == "out" and 1) or 0
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
    local a_rows, a_cols = #self.matrix, #self.matrix[1]
    local b_rows, b_cols = #tableau.matrix, #tableau.matrix[1]

    -- Copy the solution column
    for i = 1, b_rows do
        self.solution[a_rows + i] = tableau.solution[i]
    end

    -- Copy the objective row
    for j = 1, b_cols do
        self.objective[a_cols + j] = tableau.objective[j]
    end

    -- Fill the top-right section with 0
    ---@diagnostic disable: need-check-nil
    for i = 1, a_rows do
        for j = a_cols + 1, a_cols + b_cols do
            self.matrix[i][j] = 0
        end
    end

    -- Fill the bottom-left section with 0
    for i = a_rows + 1, a_rows + b_rows do
        self.matrix[i] = {}
        for j = 1, a_cols do
            self.matrix[i][j] = 0
        end
    end

    -- Copy the rest of B into A
    for i = 1, b_rows do
        for j = 1, b_cols do
            self.matrix[a_rows + i][a_cols + j] = tableau.matrix[i][j]
        end
    end

    -- Copy the row keys
    for k, v in pairs(tableau.rows) do
        local new_row = a_rows + v
        if string.sub(k, 1, 2) == "c_" then
            self.rows["c_" .. new_row] = new_row
        else
            self.rows[k] = new_row
        end
    end

    -- Copy the column keys
    for k, v in pairs(tableau.cols) do
        local new_col = a_cols + v
        -- Don't handle artificial variables
        -- If we tried to merge tableaus after starting solving, we got bigger problems
        if string.sub(k, 1, 2) == "s_" then
            self.cols["s_" .. new_col] = new_col
        else
            self.cols[k] = new_col
        end
    end
end


---@return SimplexResult result
function SimplexTableau:solve()
    local result = {
        state = "in-progress",
        products = {},
        ingredients = {},
        line_results = {},
        floor_results = {}
    }  ---@type SimplexResult

    local variable_map = {}  ---@type VariableMap[]
    local sorted_variables = {}  ---@type VariableKey[]
    local basic = {}  ---@type VariableKey[]
    local non_basic = {}  ---@type VariableKey[]

    -- Populate the column index to variable key map
    for key, column in pairs(self.cols) do
        variable_map[column] = {key = key, type = "unassigned"}
        table.insert(sorted_variables, key)
    end

    -- Sort variables descending on objective value (they are inverted in the tableau)
    table.sort(sorted_variables, function(key1, key2)
        ---@diagnostic disable: need-check-nil
        return self.objective[self.cols[key1]] < self.objective[self.cols[key2]]
    end)

    -- Mark non-0 constrained variables as non-basic
    for i = 1, #self.matrix do
        if self.solution[i] ~= 0 then
            for j = 1, #self.matrix[1] do
                if self.matrix[i][j] ~= 0 then
                    local is_basic = true
                    for k = 1, #self.matrix do
                        if k ~= i and self.matrix[k][j] ~= 0 then
                            is_basic = false
                            break
                        end
                    end
                    if not is_basic then
                        local map = variable_map[j]  ---@as VariableMap
                        if map.type == "unassigned" then
                            map.type = "non-basic"
                            table.insert(non_basic, map.key)
                        end
                    end
                end
            end
        end
    end

    -- Heuristically pick the inital basis containing the variables with the highest objective
    for _, key in pairs(sorted_variables) do
        local map = variable_map[self.cols[key]]  ---@as VariableMap
        if map.type == "unassigned" then
            for i = 1, #self.matrix do
                if self.matrix[i][self.cols[key]] > MAGIC_NUMBERS.margin_of_error and not basic[i] then
                    map.type = "basic"
                    basic[i] = key
                    break
                end
            end
        end

        -- If no row was found to form a basis for this variable, mark it as out of base
        if map.type == "unassigned" then
            map.type = "non-basic"
            table.insert(non_basic, key)
        end
    end

    -- Add a virtual variables with negative cost for each non-basic row
    for i = 1, #self.matrix do
        if not basic[i] then
            local virtual_key = "y_" .. #self.matrix[1] + 1
            local col_index = self:_add_column(virtual_key, -1e100)
            self.matrix[i][col_index] = 1
            basic[i] = virtual_key
        end
    end

    local lu  ---@type LUDecomposition
    local x_vector  ---@type number[]

    ---@return boolean done
    ---@return SolverState state
    local function pivot_step()
        -- Copy and decompose the basis matrix
        local b_matrix = {}  ---@type number[][]
        for i = 1, #self.matrix do
            b_matrix[i] = {}
            for j = 1, #basic do
                b_matrix[i][j] = self.matrix[i][self.cols[basic[j]]]
            end
        end

        lu = LUDecomposition:init(b_matrix)
        x_vector = lu:solve_right(self.solution)

        -- Compute the objective vector for the current basis
        local c_basic = {}  ---@type number[]
        for k = 1, #basic do
            c_basic[k] = self.objective[self.cols[basic[k]]]
        end
        local y_vector = lu:solve_left(c_basic)

        local a_non_basic = {}  ---@type number[][]
        for i = 1, #self.matrix do
            a_non_basic[i] = {}
            for j = 1, #non_basic do
                a_non_basic[i][j] = self.matrix[i][self.cols[non_basic[j]]]
            end
        end
        local c_non_basic = lib.matrix.left_mult(y_vector, a_non_basic)

        for j = 1, #c_non_basic do
            ---@diagnostic disable: undefined-field
            c_non_basic[j] = self.objective[self.cols[non_basic[j]]] - c_non_basic[j]
        end

        -- Select the variable with the most negative objective as the entering variable (Danzig's rule)
        -- Add a minimum margin for extra safety
        -- If there is so little score left to maximize, then the solution is pretty close to optimal anyway
        local entering_index = 0
        local min = -MAGIC_NUMBERS.margin_of_error
        for j = 1, #non_basic do
            if c_non_basic[j] < min then
                entering_index = j
                min = c_non_basic[j]  ---@as number
            end
        end

        if entering_index == 0 then
            -- We are done, but check that we don't have virtual variables in the solution
            for i = 1, #self.matrix do
                if basic[i] and string.sub(basic[i], 1, 2) == "y_" then
                    return true, "no-solution"
                end
            end
            return true, "solved"
        end

        -- Compute the coefficients of the entering variable
        ---@diagnostic disable-next-line: undefined-field
        local entering_column = self.cols[non_basic[entering_index]]  ---@type integer
        local aj_vector = {}  ---@type number[]
        for i = 1, #self.matrix do
            aj_vector[i] = self.matrix[i][entering_column]
        end
        local t_vector = lu:solve_right(aj_vector)

        -- Select the basis with the smallest ratio as the leaving variable
        local leaving_index = 0
        min = 2.0^1023
        for i = 1, #t_vector do
            if t_vector[i] > MAGIC_NUMBERS.margin_of_error then
                ---@diagnostic disable: need-check-nil
                local ratio = x_vector[i] / t_vector[i]
                if ratio < min then
                    leaving_index = i
                    min = ratio
                end
                if ratio == 0 then break end
            end
        end

        if leaving_index == 0 then return true, "unbounded" end

        -- Swap the variables
        local temp = basic[leaving_index]
        basic[leaving_index] = non_basic[entering_index]
        non_basic[entering_index] = temp

        return false, "in-progress"
    end


    -- Find a solution
    local done = false
    local iterations = 0
    local max_iterations = (#self.matrix) ^ 2  -- Upper bound is 2^#v, but average case with random pivots is #c^2
    repeat
        done, result.state = pivot_step()
        iterations = iterations + 1
    until done or iterations == max_iterations
    log("Iterations: " .. iterations)

    -- Interpret the result
    for row, key in pairs(basic) do
        local value = x_vector[row] or 0

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
    local row_index = #self.matrix + 1
    self.rows[key] = row_index
    self.matrix[row_index] = {}

    -- Handle special case when rows == 0
    if row_index == 1 then
        for _, j in pairs(self.cols) do
            self.matrix[row_index][j] = 0
        end
    end

    -- Populate the row
    self.solution[row_index] = limit or 0
    for j = 1, #self.matrix[1] do
        self.matrix[row_index][j] = 0
    end

    return row_index
end


---@private
---@param key VariableKey
---@param objective number?
---@return integer index
function SimplexTableau:_add_column(key, objective)
    local col_index = #(self.matrix[1] or {}) + 1  -- handle special case when rows == 0
    self.cols[key] = col_index

    -- Populate the column
    self.objective[col_index] = objective and -objective or 0  -- objective coefficient is opposite
    for i = 1, #self.matrix do
        self.matrix[i][col_index] = 0
    end

    return col_index
end


return SimplexTableau

local LUDecomposition = require("backend.calculation.LUDecomposition")


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"
---@alias VariableType "unassigned" | "basic" | "non-basic"
---@alias ConstraintKey string `"item_<floor_id>_<proto-key>"` | `"c_<var-key>"`
---@alias VariableKey string `"line_<line_id>"` | `"item_<floor_id>_<in|out>_<proto-key>"` | `"s_<n>"` | `"y_<n>"`
---@alias LineResultTable table<ObjectID, SimplexLineResult>
---@alias FloorResultTable table<ObjectID, SimplexFloorResult>

---@class SimplexTableau
---@field matrix number[][] column-major order
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
---@field state SolverState
---@field basis table<ConstraintKey, VariableKey>
---@field line_results LineResultTable
---@field floor_results FloorResultTable

---@class SimplexLineResult
---@field line_id ObjectID
---@field machine_amount number

---@class SimplexFloorResult
---@field floor_id ObjectID
---@field products SimplexItemList
---@field ingredients SimplexItemList


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
---@param line_data LineMetadata
function SimplexTableau:add_line_variable(line_data)
    local line_key = "line_" .. line_data.line_id

    -- Line is already present in the tableau
    if self.cols[line_key] then return end

    local col_index = self:_add_column(line_key)

    ---@param items SimplexItemList
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
                local x = self.matrix[col_index][row_index]
                self.matrix[col_index][row_index] = x + sign * value
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
    local row_index = self.rows[item_row_key]
    if not row_index then
        -- Item not present in this floor (only used in subfloor)
        row_index = self:_add_row(item_row_key)
    end

    -- Fill the table values
    local col_index = self:_add_column(item_col_key, objective)
    self.matrix[col_index]--[[@cast -nil]][row_index] = sign
end


--- Adds an additional constraint to a given item (at most one per item)
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
    local row_index = self:_add_row("c_" .. #self.matrix[1] + 1)

    -- Fill the row values
    ---@diagnostic disable: need-check-nil
    self.matrix[var_col_index][row_index] = 1
    self.solution[row_index] = limit

    -- Update the variable objective
    lib.table.add(self.objective, var_col_index, -(objective or 0))  -- objective coefficient is opposite

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column("s_" .. key)

    -- Fill the inequality between the given variable and the slack variable
    local sign = (type == "<=" and 1) or (type == ">=" and -1) or 0
    self.matrix[slack_col_index][row_index] = sign
end


---@param previous_basis table<ConstraintKey, VariableKey>
---@return SimplexResult result
function SimplexTableau:solve(previous_basis)
    local result = {
        state = "in-progress",
        basis = {},
        line_results = {},
        floor_results = {}
    }  ---@type SimplexResult

    local variable_map = {}  ---@type VariableMap[]
    local basic = {}  ---@type VariableKey[]
    local non_basic = {}  ---@type VariableKey[]

    -- Populate the column index to variable key map
    for key, column in pairs(self.cols) do
        variable_map[column] = {key = key, type = "unassigned"}
    end

    -- Populate the basis vector pased on the previous result
    local cache_valid = true
    for row_key, col_key in pairs(previous_basis) do
        local row_index = self.rows[row_key]
        local col_index = self.cols[col_key]

        if row_index and col_index then
            variable_map[col_index]--[[@cast -nil]].type = "basic"
            basic[row_index] = col_key
        elseif row_index and not col_index or not row_index and col_index then
            cache_valid = false
            break
        end
    end

    -- Check if the cache covered all the bases
    for i = 1, #self.matrix[1] do
        if not basic[i] then
            cache_valid = false
            break
        end
    end

    if not cache_valid then
        -- Reset the basis
        for i, key in pairs(basic) do
            basic[i] = nil
            variable_map[self.cols[key]]--[[@cast -nil]].type = "unassigned"
        end

        -- Find basic variables (positive coefficient in one row, 0 on the rest)
        for k = 1, #self.matrix[1] do
            if not basic[k] then
                for j = 1, #self.matrix do
                    local map = variable_map[j]  ---@as VariableMap
                    if map.type == "unassigned" and self.matrix[j][k] > MAGIC_NUMBERS.margin_of_error then
                        local is_basic = true
                        for i = 1, #self.matrix[j] do
                            if i ~= k and self.matrix[j][i] ~= 0 then
                                is_basic = false
                                break
                            end
                        end

                        if is_basic then
                            map.type = "basic"
                            basic[k] = map.key
                        else
                            map.type = "non-basic"
                            table.insert(non_basic, map.key)
                        end
                    end
                end
            end
        end

        -- Add a virtual variables with huge cost for each non-basic row
        for i = 1, #self.matrix[1] do
            if not basic[i] then
                local virtual_key = "y_" .. #self.matrix + 1
                local col_index = self:_add_column(virtual_key, -1e100)
                self.matrix[col_index]--[[@cast -nil]][i] = 1
                basic[i] = virtual_key
            end
        end
    end

    -- Mark unassigned variables as non-basic
    for _, map in ipairs(variable_map) do
        if map.type == "unassigned" then
            map.type = "non-basic"
            table.insert(non_basic, map.key)
        end
    end

    local lu  ---@type LUDecomposition
    local x_vector  ---@type number[]
    local iterations = 0
    local last_factorization = iterations
    local needs_factorization = true


    local function refactorize()
        local b_matrix = {}  ---@type number[][]
        for j = 1, #self.matrix do
            b_matrix[j] = self.matrix[self.cols[basic[j]--[[@cast -nil]]]]
        end

        local new_lu = LUDecomposition:init(b_matrix)
        if new_lu then
            lu = new_lu
            x_vector = lu:solve_right(self.solution)
            needs_factorization = false
            last_factorization = iterations
        end
    end


    ---@return boolean
    ---@return SolverState
    local function solution_reached()
        for i = 1, #basic do
            if basic[i] and string.sub(basic[i], 1, 2) == "y_" then
                return true, "no-solution"
            end
        end
        return true, "solved"
    end


    ---@return boolean done
    ---@return SolverState state
    local function iterate()
        -- Compute the objective vector for the current basis
        local c_basic = {}  ---@type number[]
        for k = 1, #basic do
            c_basic[k] = self.objective[self.cols[basic[k]]]
        end
        local y_vector = lu:solve_left(c_basic)

        local a_non_basic = {}  ---@type number[][]
        for i = 1, #self.matrix do
            a_non_basic[i] = self.matrix[self.cols[non_basic[i]--[[@cast -nil]]]]
        end
        local c_non_basic = lib.matrix.left_mult_cmo(y_vector, a_non_basic)

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

        if entering_index == 0 then return solution_reached() end

        -- Compute the coefficients of the entering variable
        local entering_column = self.cols[non_basic[entering_index]]  ---@type integer
        local d_vector = lu:solve_right(self.matrix[entering_column]--[[@cast -nil]])

        -- Select the basis with the smallest ratio as the leaving variable
        local leaving_index = 0
        min = 2.0^1023
        for i = 1, #d_vector do
            if d_vector[i] > MAGIC_NUMBERS.margin_of_error then
                local ratio = x_vector[i]--[[@cast -nil]] / d_vector[i]
                if ratio < min then
                    leaving_index = i
                    min = ratio
                elseif ratio == min and self.cols[basic[i]] < self.cols[basic[leaving_index]] then
                    -- Choose the lower variable intex to prevent cycling
                    leaving_index = i
                end
            end
        end

        if leaving_index == 0 then return true, "unbounded" end

        -- Swap the variables
        local temp = basic[leaving_index]
        basic[leaving_index] = non_basic[entering_index]
        non_basic[entering_index] = temp

        -- Update the solution
        ---@diagnostic disable-next-line: need-check-nil
        local theta = x_vector[leaving_index] / d_vector[leaving_index]
        for i = 1, #x_vector do
            if i == leaving_index then
                x_vector[i] = theta
            else
                x_vector[i] = x_vector[i]--[[@cast -nil]] - theta * d_vector[i]  ---@as number
                -- If this becomes even slightly negative, bad things will happen
                x_vector[i] = x_vector[i] > 0 and x_vector[i] or 0
            end
        end

        -- Update the decomposition
        if not lu:update(d_vector, leaving_index) then needs_factorization = true end

        return false, "in-progress"
    end


    -- Find a solution
    local done = false
    local max_iterations = (#basic) ^ 2  -- Upper bound is 2^#v, but average case with random pivots is #c^2
    local factorization_interval = math.min(#basic, MAGIC_NUMBERS.simplex_max_factorization_interval)
    repeat
        -- If the factorization is too old, we need to recreate it
        if iterations - last_factorization >= factorization_interval then
            needs_factorization = true
        end

        -- Re-factorize if needed
        if needs_factorization then refactorize() end
        if not lu then
            result.state = "no-solution"
            break
        end

        -- Cached results may already have a solution
        if #self.matrix == #self.matrix[1] then
            _, result.state = solution_reached()
            break
        end

        -- Iterate through the solution
        done, result.state = iterate()
        iterations = iterations + 1
    until done or iterations == max_iterations

    -- Calculate equivalence classes
    local equivalencies = {}  ---@type table<VariableKey, VariableKey[]>
    for _, key in pairs(basic) do equivalencies[key] = { key } end
    for dest_key, src_key in pairs(self.equality) do
        if equivalencies[src_key] then table.insert(equivalencies[src_key], dest_key) end
    end

    -- Cache the solution basis for later
    for key, i in pairs(self.rows) do
        result.basis[key] = basic[i]
    end

    -- Interpret the result
    for row, key in pairs(basic) do
        local value = x_vector[row] or 0
        if value > MAGIC_NUMBERS.margin_of_error then
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
                    }  ---@type SimplexFloorResult
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

    -- Invalidate the floor cache
    if not cache_valid then
        local invalid_columns = {}  ---@type table<VariableKey, true>
        for floor_id, _ in pairs(result.floor_results) do
            invalid_columns["line_" .. floor_id] = true
        end
        for row_key, col_key in pairs(previous_basis) do
            if invalid_columns[col_key] then previous_basis[row_key] = nil end
        end
    end

    return result
end


---@param key ConstraintKey
---@param limit number?
---@return integer index
function SimplexTableau:_add_row(key, limit)
    local row_index = #(self.matrix[1] or {}) + 1  -- handle special case when cols == 0
    self.rows[key] = row_index

    -- Populate the row
    self.solution[row_index] = limit or 0
    for j = 1, #self.matrix do
        self.matrix[j][row_index] = 0
    end

    return row_index
end


---@private
---@param key VariableKey
---@param objective number?
---@return integer index
function SimplexTableau:_add_column(key, objective)
    local col_index = #self.matrix + 1
    self.cols[key] = col_index
    self.matrix[col_index] = {}

    -- Populate the column
    self.objective[col_index] =-(objective or 0)  -- objective coefficient is opposite
    for i = 1, #self.matrix[1] do
        self.matrix[col_index][i] = 0
    end

    return col_index
end


return SimplexTableau

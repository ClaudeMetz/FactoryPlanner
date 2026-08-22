local LUDecomposition = require("backend.calculation.LUDecomposition")
local util = require("__core__.lualib.util")


---@alias InequalityType "==" | "<=" | ">="
---@alias ItemDirection "in" | "out"
---@alias SolverState "in-progress" | "solved" | "unbounded" | "no-solution"
---@alias VariableType "unassigned" | "basic" | "non-basic"
---@alias ConstraintKey string `"item;<floor_id>;<proto-key>"` | `"c;<var-key>"`
---@alias VariableKey string `"line;<line_id>"` | `"item;<floor_id>;<in|out>;<proto-key>"` | `"s;<n>"` | `"y;<n>"`
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
---@field cache_invalid boolean

---@class SimplexLineResult
---@field line_id ObjectID
---@field machine_amount number

---@class SimplexFloorResult
---@field floor_id ObjectID
---@field products SimplexItemList
---@field ingredients SimplexItemList


local SEPARATOR = ";"

---@param item_key SolverItemKey
---@param floor_id ObjectID
---@return ConstraintKey
local function pack_item_constraint(item_key, floor_id)
    return "item" .. SEPARATOR .. floor_id .. SEPARATOR .. item_key
end

---@param key string | integer
---@return ConstraintKey
local function pack_generic_constraint(key)
    return "c" .. SEPARATOR .. key
end

---@param item_key SolverItemKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@return VariableKey
local function pack_item_variable(item_key, floor_id, direction)
    return "item" .. SEPARATOR .. floor_id .. SEPARATOR .. direction .. SEPARATOR .. item_key
end

---@param line_id ObjectID
---@return VariableKey
local function pack_line_variable(line_id)
    return "line" .. SEPARATOR .. line_id
end

---@param key string | integer
---@param is_virtual boolean?
---@return VariableKey
local function pack_slack_variable(key, is_virtual)
    return (is_virtual and "y" or "s") .. SEPARATOR .. key
end

---@param key ConstraintKey | VariableKey
---@return string[]
local function unpack_key(key)
    return util.split(key--[[@as string]], SEPARATOR)
end


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
    local line_key = pack_line_variable(line_data.line_id)

    -- Line is already present in the tableau
    if self.cols[line_key] then return end

    local col_index = self:_add_column(line_key)

    ---@param items SimplexItemList
    ---@param sign 1 | -1
    local function add_rows(items, sign)
        for item, value in pairs(items) do
            if value > 0 then
                local item_row_key = pack_item_constraint(item, line_data.floor_id)
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
---@param item SolverItemKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@param objective number?
function SimplexTableau:add_item_variable(item, floor_id, direction, objective)
    local item_row_key = pack_item_constraint(item, floor_id)
    local item_col_key = pack_item_variable(item, floor_id, direction)

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
---@param item SolverItemKey
---@param floor_id ObjectID
---@param direction ItemDirection
---@param type InequalityType
---@param limit number must be non-negative (`>=0`)
---@param objective number?
function SimplexTableau:add_item_constraint(item, floor_id, direction, type, limit, objective)
    self:_add_constraint(pack_item_variable(item, floor_id, direction), type, limit, objective)
end

--- Adds an additional constraint to a given line (machine limit)
---@param line_id ObjectID
---@param type InequalityType
---@param limit number must be non-negative (`>=0`)
---@param objective number?
function SimplexTableau:add_line_constraint(line_id, type, limit, objective)
    self:_add_constraint(pack_line_variable(line_id), type, limit, objective)
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
    local row_index = self:_add_row(pack_slack_variable(#self.matrix[1] + 1))

    -- Fill the row values
    ---@diagnostic disable: need-check-nil
    self.matrix[var_col_index][row_index] = 1
    self.solution[row_index] = limit

    -- Update the variable objective
    solver.util.table.add(self.objective, var_col_index, -(objective or 0))  -- objective coefficient is opposite

    -- We are done for equality constraints
    if type == "==" then return end

    -- Add a new slack variable for the inequality
    local slack_col_index = self:_add_column(pack_generic_constraint(key))

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
        floor_results = {},
        cache_invalid = false,
    }  ---@type SimplexResult

    local variable_map = {}  ---@type VariableMap[]
    local basic = {}  ---@type VariableKey[]
    local non_basic = {}  ---@type VariableKey[]

    -- Populate the column index to variable key map
    for key, column in pairs(self.cols) do
        variable_map[column] = {key = key, type = "unassigned"}
    end

    -- Populate the basis vector based on the previous result
    for row_key, col_key in pairs(previous_basis) do
        local row_index = self.rows[row_key]
        local col_index = self.cols[col_key]

        if row_index and col_index then
            variable_map[col_index]--[[@cast -nil]].type = "basic"
            basic[row_index] = col_key
        end
    end

    -- Check if the cache covered all the bases
    for i = 1, #self.matrix[1] do
        if not basic[i] then
            result.cache_invalid = true
            break
        end
    end

    if result.cache_invalid then
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
                local virtual_key = pack_slack_variable(#self.matrix + 1, true)
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

    local lu = LUDecomposition:init(#self.matrix[1])
    local x_vector = lib.flib.shallow_copy(self.solution)
    local iterations = 0
    local last_factorization = iterations
    local needs_factorization = false

    -- Keep track of the iterations in which variables enter the basis
    local last_considered = {}  ---@type table<VariableKey, integer>
    for key, _ in pairs(self.cols) do last_considered[key] = 0 end

    local function refactorize()
        local b_matrix = {}  ---@type number[][]
        for j = 1, #self.matrix do
            b_matrix[j] = self.matrix[self.cols[basic[j]--[[@cast -nil]]]]
        end

        local new_lu = LUDecomposition:decompose(b_matrix)
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
            local var_unpacked = basic[i] and unpack_key(basic[i]) or {}
            if var_unpacked[1] == "y" then return true, "no-solution" end
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
        local c_non_basic = solver.util.matrix.left_mult_cmo(y_vector, a_non_basic)

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
        last_considered[non_basic[entering_index]] = iterations

        -- Compute the coefficients of the entering variable
        local entering_column = self.cols[non_basic[entering_index]]  ---@type integer
        local d_vector, u_vector = lu:solve_right(self.matrix[entering_column]--[[@cast -nil]])

        -- Select the basis with the smallest ratio as the leaving variable
        local leaving_index = 0
        min = math.huge
        for i = 1, #d_vector do
            if d_vector[i] > MAGIC_NUMBERS.margin_of_error then
                local ratio = x_vector[i]--[[@cast -nil]] / d_vector[i]
                if ratio < min then
                    leaving_index = i
                    min = ratio
                elseif ratio == min and last_considered[basic[i]] < last_considered[basic[leaving_index]] then
                    -- Choose the oldest variable in the basis to prevent cycling
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
        if not lu:update(u_vector, leaving_index) then needs_factorization = true end

        return false, "in-progress"
    end

    -- If a cached result was found, then we need to calculate the initial
    if result.cache_invalid then
        -- Find a solution
        local done = false
        local max_iterations = 4 * #basic
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

            -- Iterate through the solution
            done, result.state = iterate()
            iterations = iterations + 1
        until done or iterations == max_iterations
        if result.state ~= "solved" then return result end
    else
        -- Re-use the cached solution
        refactorize()
        result.state = "solved"
    end

    -- Cache the solution basis for later
    for key, i in pairs(self.rows) do
        result.basis[key] = basic[i]
    end

    -- Interpret the result
    for row, key in pairs(basic) do
        local value = x_vector[row] or 0
        if value > MAGIC_NUMBERS.margin_of_error then
            local var_unpacked = unpack_key(key)
            if var_unpacked[1] == "line" then
                local id = tonumber(var_unpacked[2])  ---@as ObjectID
                result.line_results[id] = {
                    line_id = id,
                    machine_amount = value
                }
            elseif var_unpacked[1] == "item" then
                local item_key = var_unpacked[4]  ---@as SolverItemKey
                local floor_id = tonumber(var_unpacked[2])  ---@as ObjectID

                -- Create a new floor result if necessary
                if not result.floor_results[floor_id] then
                    result.floor_results[floor_id] = {
                        floor_id = floor_id,
                        products = {},
                        ingredients = {}
                    }  ---@type SimplexFloorResult
                end

                if var_unpacked[3] == "out" then
                    result.floor_results[floor_id].products[item_key] = value
                elseif var_unpacked[3] == "in" then
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
    local row_index = #(self.matrix[1] or {}) + 1  -- handle special case when cols == 0
    self.rows[key] = row_index

    -- Populate the row
    self.solution[row_index] = limit or 0
    for j = 1, #self.matrix do
        self.matrix[j][row_index] = 0
    end

    return row_index
end

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

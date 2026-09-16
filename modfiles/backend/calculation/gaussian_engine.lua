--[[
Author: Scott Sullivan 2/23/2020
github: scottmsul

Algorithm Overview
------------------
The algorithm is based on the post here: https://kirkmcdonald.github.io/posts/calculation.html
We solve the matrix equation Ax = b, where:
    - A is a matrix whose entry in row i and col j is the output/building for item i and recipe j
      (negative is input, positive is output)
    - x is the vector of unknowns that we're solving for, and whose jth entry will be the # buildings needed for recipe j
    - b is the vector whose ith entry is the desired output for item i
Note the current implementation requires a square matrix_engine.
If there are more recipes than items, the problem is under-constrained and some recipes must be deleted.
If there are more items than recipes, the problem is over-constrained (this is more common).
    In this case we can construct "pseudo-recipes" for certrain items that produce 1/"building".
    Items with pseudo-recipes will be "free" variables that will have some constrained non-zero input or
    output after solving.
    The solved "number of buildings" will be equal to the extra input or output needed for that item.
    Typically these pseudo-recipes will be for external inputs or non-fully-recycled byproducts.
Currently the algorithm assumes any item which is part of at least one input and one output in any recipe
    is not a free variable, though the user can click on constrained items in the matrix dialog to make
    them free variables.
    The dialog calls constrained intermediate items "eliminated" since their output is constrained to zero.
If a recipe has loops, typically the user needs to make voids or free variables.
--]]

local structures = require("backend.calculation.structures")

local gaussian_engine = {}
local SEPARATOR = ";"

---@param item_key SolverItemKey
---@return string
local function pack_item_key(item_key)
    return "item"..SEPARATOR..item_key
end

---@param line_id ObjectID
---@return string
local function pack_line_key(line_id)
    return "line"..SEPARATOR..line_id
end

---@param recipe_set table<integer, true>
local function get_recipe_protos(recipe_set)
    local recipe_protos = {}
    for recipe_id, _ in pairs(recipe_set) do
        local recipe_proto = prototyper.util.find("recipes", recipe_id, nil)
        table.insert(recipe_protos, recipe_proto)
    end
    return recipe_protos
end

---@param item_set SolverSet
---@return FPItemPrototype[]
local function get_item_protos(item_set)
    local item_protos = {}  ---@type FPItemPrototype[]
    for item_key, _ in pairs(item_set) do
        local item = structures.unpack_item(item_key)
        local item_proto = prototyper.util.find("items", item.name, item.type)  ---@as FPItemPrototype
        table.insert(item_protos, item_proto)
    end
    return item_protos
end


---@class GaussianMetadata
---@field byproducts SolverSet
---@field unproduced_outputs SolverSet
---@field all_items SolverSet
---@field eliminated_items SolverSet
---@field free_items SolverSet
---@field raw_inputs SolverSet
---@field num_rows integer
---@field num_cols integer

---@param factory_data FactoryData
---@param floor_id ObjectID
---@param free_items SolverSet?
---@return GaussianMetadata
local function get_metadata(factory_data, floor_id, free_items)
    local desired_outputs = {}
    local floor_data = factory_data.floor_data_map[floor_id]
    for _, product in pairs(floor_data.products) do
        local item_key = structures.pack_item(product)
        desired_outputs[item_key] = true
    end

    local line_inputs = {}
    local line_outputs = {}
    local line_count = 0

    for _, line_data in pairs(factory_data.line_data_map) do
        for item_key, _ in pairs(line_data.ingredients) do line_inputs[item_key] = true end
        for item_key, _ in  pairs(line_data.products) do line_outputs[item_key] = true end
        line_count = line_count + 1
    end

    local all_items = solver.util.set.union(line_inputs, line_outputs)
    local raw_inputs = solver.util.set.difference(line_inputs, line_outputs)
    local raw_outputs = solver.util.set.difference(line_outputs, line_inputs)
    local byproducts = solver.util.set.difference(raw_outputs, desired_outputs)
    local unproduced_outputs = solver.util.set.difference(desired_outputs, line_outputs)
    local free_variables = solver.util.set.union(raw_inputs, byproducts, unproduced_outputs)
    local intermediate_items = solver.util.set.difference(all_items, free_variables)

    -- When a factory is updated, add any new variables to eliminated and let the user select free.
    free_items = free_items or {}
    for _, free_item in ipairs(floor_data.gaussian_free_items) do
        local item_key = structures.pack_item(free_item)
        -- Make sure that the picked free items are intermediates
        if intermediate_items[item_key] then free_items[item_key] = true end
    end

    local eliminated_items = solver.util.set.difference(intermediate_items, free_items)
    local num_rows = solver.util.set.count(raw_inputs, byproducts, eliminated_items, free_items)
    local num_cols = line_count + solver.util.set.count(raw_inputs, byproducts, free_items)
    local result = {
        byproducts = byproducts,
        unproduced_outputs = unproduced_outputs,
        all_items = all_items,
        eliminated_items = eliminated_items,
        free_items = free_items,
        raw_inputs = raw_inputs,
        num_rows = num_rows,
        num_cols = num_cols
    }  ---@type GaussianMetadata
    return result
end

---@param m number[][]
---@return number[][]
local function transpose(m)
    local transposed = {}

    if #m == 0 then
        return transposed
    end

    for i=1, #m[1] do
        local row = {}
        for j=1, #m do
            table.insert(row, m[j][i])
        end
        table.insert(transposed, row)
    end
    return transposed
end

---@class MappingStruct
---@field values string[]
---@field map table<string, integer>

---@param input_set table<string, true>
---@return MappingStruct
local function get_mapping_struct(input_set)
    -- turns a set into a mapping struct (eg matrix rows or columns)
    -- a "mapping struct" consists of a table with:
        -- key "values" - array of set values in sort order
        -- key "map" - map from input_set values to integers, where the integer is the position in "values"
    local values = {}
    for k, _ in pairs(input_set) do table.insert(values, k) end
    table.sort(values)
    local map = {}
    for i,k in ipairs(values) do
        map[k] = i
    end
    local result = {
        values = values,
        map = map
    }  ---@type MappingStruct
    return result
end

---@param factory_data FactoryData
---@param rows MappingStruct
---@param columns MappingStruct
---@param floor_id ObjectID
---@return number[][]
---@return number[]
local function get_matrix(factory_data, floor_id, rows, columns)
    -- Returns the matrix to be solved.
    -- Format is a list of lists, where outer lists are rows and inner lists are columns.
    -- Rows are items and columns are recipes (or pseudo-recipes in the case of free items).
    -- Elements have units of items/building, and are positive for outputs and negative for inputs.

    -- initialize matrix to all zeros
    local matrix = {}  ---@type number[][]
    for _=1, #rows.values do
        local row = {}  ---@type number[]
        for _=1, #columns.values+1 do -- extra +1 for desired output column
            table.insert(row, 0)
        end
        table.insert(matrix, row)
    end

    -- loop over columns since it's easier to look up items for lines/free vars than vice-versa
    for col_num=1, #columns.values do
        local col_str = columns.values[col_num]
        local col_split_str = lib.split_string(col_str, SEPARATOR)
        local col_type = col_split_str[1]
        -- note this string "item" is an internal matrix-solver convention and is unrelated to item types
        if col_type == "item" then
            local item_key = col_split_str[2]  ---@as SolverItemKey
            local row_num = rows.map[pack_item_key(item_key)]
            matrix[row_num]--[[@cast -nil]][col_num] = 1
        else -- "line"
            local line_id = col_split_str[2]  ---@as integer
            local line_data = factory_data.line_data_map[line_id]
            for item_key, amount in pairs(line_data.products) do
                ---@diagnostic disable: need-check-nil
                local row_num = rows.map[pack_item_key(item_key)]
                matrix[row_num][col_num] = matrix[row_num][col_num] + amount
            end

            for item_key, amount in pairs(line_data.ingredients) do
                ---@diagnostic disable: need-check-nil
                local row_num = rows.map[pack_item_key(item_key)]
                matrix[row_num][col_num] = matrix[row_num][col_num] - amount
            end
        end
    end

    -- final column for desired output. Don't have to explicitly set constrained vars to zero
    -- since matrix is initialized with zeros.
    local floor_data = factory_data.floor_data_map[floor_id]
    for _, product in ipairs(floor_data.products) do
        if floor_data.level == 1 then
            local item_key = structures.pack_item(product)
            local row_num = rows.map[pack_item_key(item_key)]  -- will be nil for unproduced outputs
            if row_num ~= nil then
                local amount = product.amount
                matrix[row_num]--[[@cast -nil]][#columns.values+1] = amount
            end
        end
    end

    -- we rescale free items such that "1" is equal to the max value of its unit in any other equations
    -- required to help mitigate issues with large units such as energy which can be greater than 10^9 in certain recipes
    -- also rescale the matrix such that the max value is 1 in any row, which helps for the transpose solve
    local free_variables = {}  ---@type integer[]
    for col = 1, #columns.values do
        local num_non_zero = 0
        local row_containing_free_variable = 0
        for row = 1, #rows.values do
            if matrix[row]--[[@cast -nil]][col] ~= 0 then
                num_non_zero = num_non_zero + 1
                row_containing_free_variable = row
            end
        end
        if num_non_zero == 1 then
            free_variables[col] = row_containing_free_variable
        end
    end

    local free_variable_scale_factors = {}
    for row = 1, #rows.values do
        local max_row_value = 0.0
        for col = 1, #columns.values+1 do
            local row_value = math.abs(matrix[row]--[[@cast -nil]][col]--[[@cast -nil]])
            if (free_variables[col] == nil) and (row_value > max_row_value) then
                max_row_value = row_value
            end
        end
        if max_row_value > 0 then
            for col = 1, #columns.values+1 do
                ---@diagnostic disable: need-check-nil
                if (free_variables[col] == nil) then
                    matrix[row][col] = matrix[row][col] / max_row_value
                elseif (free_variables[col] == row) then
                    free_variable_scale_factors[col] = max_row_value
                end
            end
        end
    end

    return matrix, free_variable_scale_factors
end

---@class MatrixData
---@field matrix number[][]
---@field rows MappingStruct
---@field columns MappingStruct
---@field free_variables table<string, true>
---@field free_variable_scale_factors number[]

---@param factory_data FactoryData
---@param metadata GaussianMetadata
---@param floor_id ObjectID
---@return MatrixData
local function get_matrix_data(factory_data, metadata, floor_id)
    -- Storing the line keys as "line;(lines id)"
    local line_names = {}  ---@type table<string, true>
    for line_id, _ in pairs(factory_data.line_data_map) do
        line_names[pack_line_key(line_id)] = true
    end

    -- Generate row (constraint) data
    local item_constraints = {}
    for key, _ in pairs(metadata.all_items) do item_constraints[pack_item_key(key)] = true end
    local row_set = solver.util.set.union(item_constraints)
    local rows = get_mapping_struct(row_set)

    -- Generate column (variable) data
    local variable_set = solver.util.set.union(metadata.free_items, metadata.raw_inputs, metadata.byproducts)  ---@as SolverSet
    local item_variables = {}  ---@type table<string, true>
    for key, _ in pairs(variable_set) do item_variables[pack_item_key(key)] = true end
    local column_set = solver.util.set.union(line_names, item_variables)
    local columns = get_mapping_struct(column_set)

    local matrix, free_variable_scale_factors = get_matrix(factory_data, floor_id, rows, columns)

    return {
        matrix = matrix,
        rows = rows,
        columns = columns,
        free_variables = item_variables,
        free_variable_scale_factors = free_variable_scale_factors
    }  ---@type MatrixData
end

-- Contains the raw matrix solver. Converts an NxN+1 matrix to reduced row-echelon form.
-- Based on the algorithm from octave: https://fossies.org/dox/FreeMat-4.2-Source/rref_8m_source.html
---@param m number[][]
local function to_reduced_row_echelon_form(m)
    ---@diagnostic disable: need-check-nil
    local num_rows = #m
    if #m==0 then return m end
    local num_cols = #m[1]

    local tolerance = MAGIC_NUMBERS.matrix_tolerance
    local pivot_row = 1

    for curr_col = 1, num_cols do
        -- find row with highest value in curr col as next pivot
        local max_pivot_index = pivot_row
        local max_pivot_value = math.abs(m[pivot_row][curr_col]--[[@cast -nil]])
        for curr_row = pivot_row+1, num_rows do
            local curr_pivot_value = math.abs(m[curr_row][curr_col]--[[@cast -nil]])
            if curr_pivot_value > max_pivot_value then
                max_pivot_index = curr_row
                max_pivot_value = curr_pivot_value
            end
        end

        if max_pivot_value < tolerance then
            -- if highest value is approximately zero, set this row and all rows below to zero
            for zero_row = pivot_row, num_rows do
                m[zero_row][curr_col] = 0
            end
        else
            -- swap current row with highest value row
            local temp = m[pivot_row]
            m[pivot_row] = m[max_pivot_index]
            m[max_pivot_index] = temp

            -- find nonzero cols in this row for the elimination step and normalize
            local nonzero_pivot_cols = {}
            local factor = m[pivot_row][curr_col]
            m[pivot_row][curr_col] = m[pivot_row][curr_col] / factor
            for update_col = curr_col+1, num_cols do
                local curr_pivot_col_value = m[pivot_row][update_col]
                if curr_pivot_col_value ~= 0 then
                    curr_pivot_col_value = curr_pivot_col_value / factor
                    m[pivot_row][update_col] = curr_pivot_col_value
                    nonzero_pivot_cols[update_col] = curr_pivot_col_value
                end
            end

            -- eliminate current column from other rows
            for update_row = 1, pivot_row - 1 do
                if m[update_row][curr_col] ~= 0 then
                    for update_col, pivot_col_value in pairs(nonzero_pivot_cols) do
                        m[update_row][update_col] = m[update_row][update_col] - m[update_row][curr_col]*pivot_col_value
                    end
                    m[update_row][curr_col] = 0
                end
            end
            for update_row = pivot_row+1, num_rows do
                if m[update_row][curr_col] ~= 0 then
                    for update_col, pivot_col_value in pairs(nonzero_pivot_cols) do
                        m[update_row][update_col] = m[update_row][update_col] - m[update_row][curr_col]*pivot_col_value
                    end
                    m[update_row][curr_col] = 0
                end
            end

            -- only add 1 if there is another leading 1 row
            pivot_row = pivot_row + 1

            if pivot_row > num_rows then
                break
            end
        end
    end
end

---@param matrix number[][]
---@param ignore_last boolean
---@return table<integer, true>
local function find_linearly_dependent_cols(matrix, ignore_last)
    -- Returns linearly dependent columns from a row-reduced matrix
    -- Algorithm works as follows:
    -- For each column:
    --      If this column has a leading 1, track which row maps to this column using the ones_map variable (eg cols 1, 2, 3, 5)
    --      Otherwise, this column is linearly dependent (eg col 4)
    --          For any non-zero rows in this col, the col which contains that row's leading 1 is also linearly dependent
    --                    (eg for col 4, we have row 2 -> col 2 and row 3 -> col 3)
    -- The example below would give cols 2, 3, 4 as being linearly dependent (x's are non-zeros)
    -- 1 0 0 0 0
    -- 0 1 x x 0
    -- 0 0 1 x 0
    -- 0 0 0 0 1
    -- I haven't proven this is 100% correct, this is just something I came up with
    local row_index = 1
    local num_rows = #matrix
    local num_cols = #matrix[1]
    if ignore_last then
        num_cols = num_cols - 1
    end
    local ones_map = {}  ---@type integer[]
    local col_set = {}  ---@type table<integer, true>
    for col_index=1, num_cols do
        ---@diagnostic disable: need-check-nil
        if (row_index <= num_rows) and (matrix[row_index][col_index]==1) then
            ones_map[row_index] = col_index
            row_index = row_index+1
        else
            col_set[col_index] = true
            for i=1, row_index-1 do
                if matrix[i][col_index] ~= 0 then
                    col_set[ones_map[i]] = true
                end
            end
        end
    end
    return col_set
end

---@class LinearDependanceData
---@field linearly_dependent_recipes FPRecipePrototype[]
---@field linearly_dependent_free_items FPItemPrototype[]
---@field allowed_free_items FPItemPrototype[]
---@field num_needed_free_items integer

---@param factory_data FactoryData
---@param metadata GaussianMetadata
---@param floor_id ObjectID
---@return LinearDependanceData
local function get_linear_dependence_data(factory_data, metadata, floor_id)
    local num_rows = metadata.num_rows
    local num_cols = metadata.num_cols

    local linearly_dependent_recipes = {}  ---@type table<integer, true>
    local linearly_dependent_free_items = {}  ---@type SolverSet
    local allowed_free_items = {}  ---@type SolverSet

    local matrix_data = get_matrix_data(factory_data, metadata, floor_id)
    local matrix = matrix_data.matrix
    local columns = matrix_data.columns
    to_reduced_row_echelon_form(matrix)

    local linearly_dependent_cols = find_linearly_dependent_cols(matrix, true)
    local linearly_dependent_variables = {}  ---@type table<string, true>

    for col, _ in pairs(linearly_dependent_cols) do  ---@cast col integer
        local col_name = columns.values[col]  ---@as string
        local col_split_str = lib.split_string(col_name, SEPARATOR)
        if col_split_str[1] == "line" then
            local line_id = col_split_str[2]  ---@as integer
            local recipe_name = factory_data.line_data_map[line_id].recipe_name
            linearly_dependent_variables["recipe"..SEPARATOR..recipe_name] = true
        else -- item
            linearly_dependent_variables[col_name] = true
        end
    end

    if next(linearly_dependent_variables) ~= nil then
        local free_items = metadata.free_items

        for col_name, _ in pairs(linearly_dependent_variables) do
            local col_split_str = lib.split_string(col_name, SEPARATOR)
            if col_split_str[1] == "recipe" then
                local recipe_key = col_split_str[2]  ---@as integer
                linearly_dependent_recipes[recipe_key] = true
            else -- "item"
                local item_key = col_split_str[2]  ---@as SolverItemKey
                if free_items[item_key] then linearly_dependent_free_items[item_key] = true end
            end
        end
    end
    -- check which eliminated items could be made free while still retaining linear independence
    if next(linearly_dependent_variables) == nil and num_cols < num_rows then
        local ld_matrix_data = get_matrix_data(factory_data, metadata, floor_id)
        local items = ld_matrix_data.rows  -- when transposed becomes columns

        local t_matrix = transpose(ld_matrix_data.matrix)
        table.remove(t_matrix)
        to_reduced_row_echelon_form(t_matrix)
        local t_linearly_dependent = find_linearly_dependent_cols(t_matrix, false)
        local eliminated_items = metadata.eliminated_items

        for col, _ in pairs(t_linearly_dependent) do  ---@cast col integer
            local row_split_str = lib.split_string(items.values[col]--[[@cast -nil]], SEPARATOR)
            if row_split_str[1] == "item" then
                local item_key = row_split_str[2]  ---@as SolverItemKey
                if eliminated_items[item_key] then allowed_free_items[item_key] = true end
            end
        end
    end

    local num_chosen_free_items = 0
    for _, _ in pairs(metadata.free_items) do num_chosen_free_items = num_chosen_free_items + 1 end

    local result = {
        linearly_dependent_recipes = get_recipe_protos(linearly_dependent_recipes),
        linearly_dependent_free_items = get_item_protos(linearly_dependent_free_items),
        allowed_free_items = get_item_protos(allowed_free_items),
        num_needed_free_items = num_rows - num_cols + num_chosen_free_items
    }  ---@type LinearDependanceData
    return result
end

---@param line_data LineData
---@param machine_amount number
---@param metadata GaussianMetadata
---@param free_variables table<string, true>
---@return SolverAggregate
local function get_line_result_aggregate(line_data, machine_amount, metadata, free_variables)
    local aggregate = structures.aggregate.init(line_data.floor_id)

    -- Metadata aggregates assumed a machine amount of 1, so we just need to multiply by the solved machine amount to get the result
    aggregate.machine_amount = machine_amount
    aggregate.crafts_per_second = machine_amount * line_data.crafts_per_second

    for item_key, item_amount in pairs(line_data.products) do
        if metadata.byproducts[item_key] or free_variables[pack_item_key(item_key)] then
           aggregate.byproducts[item_key] = item_amount * machine_amount
           aggregate.products[item_key] = nil
        else
           aggregate.products[item_key] = item_amount * machine_amount
        end
    end

    for item_key, item_amount in pairs(line_data.ingredients) do
        aggregate.ingredients[item_key] = item_amount * machine_amount
    end

    return aggregate
end

---@param factory_data FactoryData
---@param metadata GaussianMetadata
---@param floor_id ObjectID
---@return table<string, true>?
local function run_solver(factory_data, metadata, floor_id)
    local matrix_data = get_matrix_data(factory_data, metadata, floor_id)
    local matrix = matrix_data.matrix
    local columns = matrix_data.columns
    local free_variables = matrix_data.free_variables
    local free_variable_scale_factors = matrix_data.free_variable_scale_factors

    to_reduced_row_echelon_form(matrix)

    -- rescale ouput column based on free variable scale factors
    for idx, scale_factor in pairs(free_variable_scale_factors) do
        ---@diagnostic disable: need-check-nil
        matrix[idx][#columns.values+1] = matrix[idx][#columns.values+1] * scale_factor
    end

    -- If an aggregate has items that are both inputs and outputs, deletes whichever is smaller and saves the net amount.
    -- If the input and output are identical to within rounding error, delete from both.
    -- This is mainly for calculating line aggregates with subfloors for the matrix solver.
    ---@param aggregate SolverAggregate
    local function consolidate(aggregate)
        structures.map.reduce_items(aggregate.products, aggregate.ingredients, true)
        structures.map.reduce_items(aggregate.byproducts, aggregate.ingredients, true)
    end

    ---@param floor_id ObjectID
    local function set_line_results(floor_id)
        local floor_data = factory_data.floor_data_map[floor_id]
        local floor_aggregate = structures.aggregate.init(floor_id)
        for _, line_object_id in ipairs(floor_data.line_ids) do
            local line_key = pack_line_key(line_object_id)
            local line_data = nil
            local line_aggregate = nil
            if factory_data.line_data_map[line_object_id] then  -- Line
                local col_num = columns.map[line_key]
                 -- want the j-th entry in the last column (output of row-reduction)
                local machine_amount = matrix[col_num]--[[@cast -nil]][#columns.values+1]  ---@as number
                if machine_amount < 0 then machine_amount = 0 end
                line_data = factory_data.line_data_map[line_object_id]
                line_aggregate = get_line_result_aggregate(line_data, machine_amount, metadata, free_variables)
            else  -- Floor
                line_aggregate = set_line_results(line_object_id)
                consolidate(line_aggregate)
            end

            -- Lines with subfloors show actual number of machines to build, so each counts are rounded up when summed
            floor_aggregate.machine_amount = floor_aggregate.machine_amount +
                math.ceil(line_aggregate.machine_amount - MAGIC_NUMBERS.margin_of_error)

            for _, map in pairs{"products", "byproducts", "ingredients"} do
                for _, item in pairs(structures.map.list(line_aggregate[map])) do
                    structures.map.add(floor_aggregate[map], item)
                end
            end

            -- remove fuel from Ingredient for display only
            local fuel_amount = nil
            if line_data and line_data.fuel_item then
                fuel_amount = line_data.fuel_item.amount * line_aggregate.machine_amount
                structures.map.subtract(line_aggregate.ingredients, line_data.fuel_item, fuel_amount, true)
            end

            -- need to call consolidate before set_line_result to net any non-fuel catalysts for display
            consolidate(line_aggregate)

            solver.set_line_result {
                floor_id = floor_id,
                line_id = line_object_id,
                machine_amount = line_aggregate.machine_amount,
                crafts_per_second = line_aggregate.crafts_per_second,
                products = line_aggregate.products,
                byproducts = line_aggregate.byproducts,
                ingredients = line_aggregate.ingredients,
                fuel_amount = fuel_amount
            }
        end
        return floor_aggregate
    end

    local floor_aggregate = set_line_results(floor_id)

    -- Nets out items that are produced and consumed in equal amounts across the whole factory,
    -- while the amounts on both sides are still around to tell solver noise from a real leftover
    consolidate(floor_aggregate)

    local total = {}
    for _, item in ipairs(structures.map.list(floor_aggregate.products)) do
        structures.map.add(total, item)
    end
    for _, item in ipairs(structures.map.list(floor_aggregate.byproducts)) do
        structures.map.add(total, item)
    end
    for _, item in ipairs(structures.map.list(floor_aggregate.ingredients)) do
        structures.map.subtract(total, item)
    end

    local floor_data = factory_data.floor_data_map[floor_id]
    local required_amount = {}
    for _, product in pairs(floor_data.products) do
        local key = structures.pack_item(product)
        required_amount[key] = product.amount
    end

    local main_aggregate = structures.aggregate.init(floor_id)
    for _, item in ipairs(structures.map.list(total)) do
        local key = structures.pack_item(item)
        local req = required_amount[key] or 0
        local amount = item.amount - req
        -- A product that comes out to its required amount shouldn't leave a leftover either
        if math.abs(amount) < math.abs(req) * MAGIC_NUMBERS.margin_of_error then amount = 0 end

        if amount > 0 then
            structures.map.add(main_aggregate.byproducts, item, amount)
        else
            structures.map.add(main_aggregate.ingredients, item, -amount)
        end
    end

    -- set products for unproduced items
    for _, product in pairs(floor_data.products) do
        local item_key = structures.pack_item(product)
        if not metadata.unproduced_outputs[item_key] then
            structures.map.add(main_aggregate.products, product)
        end
    end

    solver.set_factory_result {
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        products = main_aggregate.products,
        byproducts = main_aggregate.byproducts,
        ingredients = main_aggregate.ingredients
    }
end

---@param factory_data FactoryData
---@param floor_id ObjectID
function gaussian_engine.solve_floor(factory_data, floor_id)
    local factory = OBJECT_INDEX[factory_data.factory_id]  ---@as Factory
    local player = game.players[factory_data.player_index]
    local floor = OBJECT_INDEX[floor_id]  ---@as Floor

    local metadata = get_metadata(factory_data, floor_id)

    if metadata.num_rows ~= 0 then  -- don't run calculations if the factory has no lines
        local linear_dependence_data = get_linear_dependence_data(factory_data, metadata, floor_id)

        -- In the case of linearly dependent free items, we remove it automatically if there's only one option.
        -- Otherwise we present the user with a choice to remove problematic free items in the production box.
        local num_ld_free_items, last_ld_free_item = 0, nil  ---@type integer, FPItemPrototype?
        for _, ld_free_item in pairs(linear_dependence_data.linearly_dependent_free_items) do
            num_ld_free_items = num_ld_free_items + 1
            last_ld_free_item = ld_free_item
        end
        if num_ld_free_items == 1 then  ---@cast last_ld_free_item -nil
            metadata.free_items[structures.pack_item(last_ld_free_item)] = nil

            -- Redo all these since we've changed the factory
            metadata = get_metadata(factory_data, floor_id, metadata.free_items)
            linear_dependence_data = get_linear_dependence_data(factory_data, metadata, floor_id)
        end

        if metadata.num_rows == metadata.num_cols
                and #linear_dependence_data.linearly_dependent_recipes == 0 then
            run_solver(factory_data, metadata, floor_id)
        else
            solver.set_blank_factory(player, factory)  -- reset factory by blanking everything
        end
        floor.linear_dependence_data = linear_dependence_data
        floor.gaussian_free_items = get_item_protos(metadata.free_items)
    else  -- reset top level items
        solver.set_blank_factory(player, factory)
        floor.linear_dependence_data = nil
        floor.gaussian_free_items = {}
    end
end

return gaussian_engine

--[[
Author: Scott Sullivan 2/23/2020
github: scottmsul

Algorithm Overview
------------------
The algorithm is based on the post here: https://kirkmcdonald.github.io/posts/calculation.html
We solve the matrix equation Ax = b, where:
    - A is a matrix whose entry in row i and col j is the output/sec/building for item i and recipe j (negative is input, positive is output)
    - x is the vector of unknowns that we're solving for, and whose jth entry will be the # buildings needed for recipe j
    - b is the vector of whose ith entry is the desired output/sec for item i
Note the current implementation requires a square matrix.
If there are more recipes than items, the problem is under-constrained and some recipes must be deleted.
If there are more items than recipes, the problem is over-constrained (this is more common).
    In this case we can construct "pseudo-recipes" for certrain items that produce 1/sec/"building".
    Items with pseudo-recipes will be "free" variables that will have some constrained non-zero input or output after solving.
    The "solution" will be equal to the extra input or output for that item.
    Typically these pseudo-recipes will be for external inputs or non-recycled by-products.
Currently the algorithm assumes any item which is part of at least one input and one output in any recipe is not a free variable,
    though this could be updated to make the choice free variables more customizable.
If a recipe has loops, typically the user needs to make voids.
--]]
matrix_solver = {}

-- for our purposes the string "(item type id)_(item id)" is what we're calling the "item_id"
function get_item_id(obj)
    local item_type_name = obj.type
    local item_name = obj.name
    local item_type_id = global.all_items.map[item_type_name]
    local item_id = global.all_items.types[item_type_id].map[item_name]
    return tostring(item_type_id)..'_'..tostring(item_id)
end

function matrix_solver.get_items(subfactory_data)
    local recipe_inputs = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "ingredients", type = "list"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local recipe_main_products = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "main_product", type = "value"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local recipe_products = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "products", type = "list"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local desired_outputs = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "proto", type = "value"},
        {key = "top_level_products", type = "list"}
    })
    local recipe_outputs = matrix_solver.union_sets(recipe_main_products, recipe_products)
    local all_items = matrix_solver.union_sets(recipe_inputs, recipe_outputs, desired_outputs)
    local raw_inputs = matrix_solver.set_diff(recipe_inputs, recipe_outputs)
    local by_products = matrix_solver.set_diff(matrix_solver.set_diff(recipe_outputs, recipe_inputs), desired_outputs)
    local unproduced_outputs = matrix_solver.set_diff(desired_outputs, recipe_outputs)
    local initial_free_variables = matrix_solver.union_sets(raw_inputs, by_products, unproduced_outputs)
    local initial_constrained_variables = matrix_solver.set_diff(all_items, initial_free_variables)
    return {
        free = matrix_solver.set_to_ordered_list(initial_free_variables),
        constrained = matrix_solver.set_to_ordered_list(initial_constrained_variables)
    }
end

function matrix_solver.set_diff(a, b)
    local result = {}
    for k, _ in pairs(a) do
        if not b[k] then
            result[k] = true
        end
    end
    return result
end

-- recursively iterates through the struct using the keys
-- returns a set with the values, represented as a table with each key set to true
function matrix_solver.extract_set(struct, keys)
    local inner_keys = cutil.shallowcopy(keys)
    local curr_key = table.remove(inner_keys)

    local curr_key_name = curr_key["key"]
    local curr_key_type = curr_key["type"]
    if curr_key_type == "value" then
        if struct[curr_key_name] == nil then return {} end
        local inner_struct = struct[curr_key_name]
        local result = matrix_solver.extract_set(inner_struct, inner_keys)
        return result
    elseif curr_key_type == "list" then
        if struct[curr_key_name] == nil then return {} end
        local result = {}
        for k, inner_struct in pairs(struct[curr_key_name]) do
            if inner_struct == nil then
                return {}
            end
            local curr_result = matrix_solver.extract_set(inner_struct, inner_keys)
            for k, v in pairs(curr_result) do
                result[k] = v
            end
        end
        return result
    -- base case
    elseif curr_key_type == "function" then
        local result = {}
        result[curr_key_name(struct)] = true
        return result
    end
end

function matrix_solver.union_sets(...)
    local arg = {...}
    local result = {}
    for _, set in ipairs(arg) do
        for val, _ in pairs(set) do
            result[val] = true
        end
    end
    return result
end

-- not even used :/
function matrix_solver.intersect_sets(...)
    local arg = {...}
    local counts = {}
    local num_sets = #arg
    for _, set in ipairs(arg) do
        for val, _ in pairs(set) do
            if not counts[val] then
                counts[val] = 1
            else
                counts[val] = counts[val] + 1
            end
        end
    end
    local result = {}
    for k, count in pairs(counts) do
        if count==num_sets then
            result[k] = true
        end
    end
    return result
end

function matrix_solver.run_matrix_solver(player, subfactory_data, variables)
    local recipe_inputs = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "ingredients", type = "list"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local recipe_main_products = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "main_product", type = "value"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local recipe_products = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "products", type = "list"},
        {key = "recipe_proto", type = "value"},
        {key = "lines", type = "list"},
        {key = "top_floor", type = "value"}})
    local desired_outputs = matrix_solver.extract_set(subfactory_data, {
        {key = get_item_id, type = "function"},
        {key = "proto", type = "value"},
        {key = "top_level_products", type = "list"}
    })
    local all_items = matrix_solver.union_sets(recipe_inputs, recipe_main_products, recipe_products, desired_outputs)
    local rows = matrix_solver.get_mapping_struct(all_items)
    local lines = {}
    for i=1, #subfactory_data.top_floor.lines do lines["line_"..i]=true end
    local free_variables = {}
    for i, v in ipairs(variables.free) do
        free_variables["item_"..v] = true
    end
    local col_set = matrix_solver.union_sets(lines, free_variables)
    local columns = matrix_solver.get_mapping_struct(col_set)
    local matrix = matrix_solver.get_matrix(subfactory_data, rows, columns)
    llog('ROWS')
    llog(rows)
    llog('COLUMNS')
    llog(columns)
    llog('MATRIX BEFORE')
    matrix_solver.print_matrix(matrix)

    matrix_solver.to_reduced_row_echelon_form(matrix)
    llog('MATRIX AFTER')
    matrix_solver.print_matrix(matrix)

    local aggregate = structures.aggregate.init(subfactory_data.player_index, 1)
    for _, product in ipairs(subfactory_data.top_level_products) do
        structures.aggregate.add(aggregate, "Product", product)
    end

    -- need to call the following functions:
    -- calculation.interface.set_line_result for each line (see bottom of model.lua)
    -- calculation.interface.set_subfactory_result for summary results (see top of model.lua)
    -- both of these require creating aggregate and class objects from structures.lua
    for col_num=1, #columns.values do
        local col_str = columns.values[col_num]
        local col_split_str = cutil.split(col_str, "_")
        local col_type = col_split_str[1]
        if col_type == "item" then
            -- local item_id = col_split_str[2].."_"..col_split_str[3]
            -- local row_num = rows.map[item_id]
            -- matrix[row_num][col_num] = 1
        -- "line"
        else
            -- local line_aggregate = structures.aggregate.init(subfactory_data.player_index, 1)
            -- the index in the subfactory_data.top_floor.lines table can be different from the line_id!
            local lines_table_id = col_split_str[2]
            local line = subfactory_data.top_floor.lines[lines_table_id]
            local line_id = line.id
            local machine_count = matrix[col_num][#columns.values+1] -- want the jth entry in the last column (output of row-reduction)
            local line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, machine_count)

            calculation.interface.set_line_result {
                player_index = player.index,
                floor_id = 1, --TODO: set this properly
                line_id = line_id,
                machine_count = machine_count,
                energy_consumption = line_aggregate.energy_consumption,
                pollution = line_aggregate.pollution,
                production_ratio = 1,
                uncapped_production_ratio = 1,
                -- see if this works
                Product = line_aggregate.Product,
                Byproduct = structures.class.init(),
                Ingredient = line_aggregate.Ingredient
                -- Fuel = structures.class.init()
            }
        end
    end
end

function matrix_solver.get_matrix(subfactory_data, rows, columns)
    -- Returns the matrix to be solved.
    -- Format is a list of lists, where outer lists are rows and inner lists are columns.
    -- Rows are items and columns are recipes (or pseudo-recipes in the case of free items).
    -- Elements have units of items/timescale/building, and are positive for outputs and negative for inputs.

    -- initialize matrix to all zeros
    local matrix = {}
    for i=1, #rows.values do
        local row = {}
        for j=1, #columns.values+1 do -- extra +1 for desired output column
            table.insert(row, 0)
        end
        table.insert(matrix, row)
    end

    -- loop over columns since it's easier to look up items for lines/free vars than vice-versa
    for col_num=1, #columns.values do
        local col_str = columns.values[col_num]
        local col_split_str = cutil.split(col_str, "_")
        local col_type = col_split_str[1]
        if col_type == "item" then
            local item_id = col_split_str[2].."_"..col_split_str[3]
            local row_num = rows.map[item_id]
            matrix[row_num][col_num] = 1
        -- "line"
        else
            local line_id = col_split_str[2]
            local line = subfactory_data.top_floor.lines[line_id]
            -- "energy" is the recipe's raw crafting time
            local energy = line.recipe_proto.energy
            local timescale = line.timescale
            local crafting_speed = line.machine_proto.speed

            -- add ingredients
            for _, ingredient in ipairs(line.recipe_proto.ingredients) do
                local item_id = get_item_id(ingredient)
                local row_num = rows.map[item_id]
                local amount = ingredient.amount
                matrix[row_num][col_num] = matrix[row_num][col_num] - amount * energy * crafting_speed
            end

            -- todo - add modules and beacons
            -- also probably need to add timescale

            -- add main output
            local main_product = line.recipe_proto.main_product
            local item_id = get_item_id(main_product)
            local row_num = rows.map[item_id]
            local amount = main_product.amount
            matrix[row_num][col_num] = matrix[row_num][col_num] + amount * crafting_speed * timescale / energy
        end
    end

    -- final column for desired output. Don't have to explicitly set constrained vars to zero since matrix is initialized with zeros.
    for _, product in ipairs(subfactory_data.top_level_products) do
        local item_id = product.proto.identifier
        local row_num = rows.map[item_id]
        local amount = product.required_amount
        matrix[row_num][#columns.values+1] = amount
    end

    return matrix
end

function matrix_solver.get_line_aggregate(line, player_index, machine_count)
    local line_aggregate = structures.aggregate.init(player_index, 1)
    -- the index in the subfactory_data.top_floor.lines table can be different from the line_id!
    local recipe_proto = line.recipe_proto
    local timescale = line.timescale
    local amount_per_timescale = machine_count * timescale * line.machine_proto.speed / recipe_proto.energy
    structures.aggregate.add(line_aggregate, "Product", recipe_proto.main_product, recipe_proto.main_product.amount * amount_per_timescale)
    for _, product in pairs(recipe_proto.products) do
        structures.aggregate.add(line_aggregate, "Byproduct", product, product.amount * amount_per_timescale)
    end
    for _, ingredient in pairs(recipe_proto.ingredients) do
        structures.aggregate.add(line_aggregate, "Ingredient", ingredient, ingredient.amount * amount_per_timescale)
    end
    line_aggregate.energy_consumption = line.machine_proto.energy_usage * machine_count * timescale
    line_aggregate.pollution = line.machine_proto.emissions * machine_count * timescale
    return line_aggregate
end

function matrix_solver.print_matrix(m)
    s = ""
    s = s.."{\n"
    for i,row in ipairs(m) do
        s = s.."  {"
        for j,col in ipairs(row) do
            s = s..(col)
            if j<#row then
                s = s.." "
            end
        end
        s = s.."}\n"
    end
    s = s.."}"
    llog(s)
end

function matrix_solver.get_mapping_struct(input_set)
    -- turns a set into a mapping struct (eg matrix rows or columns)
    -- a "mapping struct" consists of a table with:
        -- key "values" - array of set values in sort order
        -- key "map" - map from input_set values to integers, where the integer is the position in "values"
    local values = matrix_solver.set_to_ordered_list(input_set)
    local map = {}
    for i,k in ipairs(values) do
        map[k] = i
    end
    local result = {
        values = values,
        map = map
    }
    return result
end

function matrix_solver.set_to_ordered_list(s)
    local result = {}
    for k, _ in pairs(s) do table.insert(result, k) end
    table.sort(result)
    return result
end

-- Contains the raw matrix solver. Converts an NxN+1 matrix to reduced row-echelon form.
function matrix_solver.to_reduced_row_echelon_form(m)
    local num_rows = #m
    local num_cols = #m[1]

    -- BEGIN ECHELON FORM PART - this makes an upper triangular matrix with all leading 1s
    local pivot_row = 1

    for curr_col = 1, num_cols do
        local first_nonzero_row = 0

        -- check if curr_col has any zeros
        for curr_row = pivot_row, num_rows do
            if m[curr_row][curr_col] ~= 0 then
                first_nonzero_row = curr_row
                break
            end
        end

        -- if all the cols are zero we do nothing
        if first_nonzero_row ~= 0 then
            -- swap pivot_row and first_nonzero_row
            local temp = m[pivot_row]
            m[pivot_row] = m[first_nonzero_row]
            m[first_nonzero_row] = temp

            -- divide the row so the first entry is 1
            local factor = m[pivot_row][curr_col]
            for j = curr_col, num_cols do
                m[pivot_row][j] = m[pivot_row][j] / factor
            end

            -- subtract from the remaining rows so their first entries are zero
            for i = first_nonzero_row+1, num_rows do
                local factor = m[i][curr_col]
                for j = curr_col, num_cols do
                    m[i][j] = m[i][j] - m[pivot_row][j] * factor
                end
            end

            -- only add 1 if get another leading 1 row
            pivot_row = pivot_row + 1
        end
    end
    -- END ECHELON FORM PART

    -- BEGIN REDUCED ROW ECHELON FORM PART - this fills out the rest of the zeros in the upper part of the upper triangular matrix
    for curr_row = 1, num_rows do
        local first_nonzero_col = 0
        for curr_col = 1, num_cols do
            if m[curr_row][curr_col] == 1 then
                first_nonzero_col = curr_col
                break
            end
        end
        -- if all the cols are zero we do nothing
        if first_nonzero_col ~= 0 then
            -- subtract curr_row from previous rows to make leading entry a 0
            for i = 1, curr_row-1 do
                factor = m[i][first_nonzero_col]
                for j = first_nonzero_col, num_cols do
                    m[i][j] = m[i][j] - m[curr_row][j] * factor
                end
            end
        end
    end
    -- END REDUCED ROW ECHELON FORM PART
end

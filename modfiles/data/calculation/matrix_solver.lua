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
function matrix_solver.get_item_key(item_type_name, item_name)
    local item_type_id = global.all_items.map[item_type_name]
    local item_id = global.all_items.types[item_type_id].map[item_name]
    return tostring(item_type_id)..'_'..tostring(item_id)
end

-- this is really only used for debugging
function matrix_solver.get_item_name(item_key)
    local split_str = cutil.split(item_key, "_")
    local item_type_id = split_str[1]
    local item_id = split_str[2]
    local item_info = global.all_items.types[item_type_id].items[item_id]
    return item_info.type.."_"..item_info.name
end

function matrix_solver.get_item_names(items)
    item_name_set = {}
    for k, _ in pairs(items) do
        local item_name = matrix_solver.get_item_name(k)
        item_name_set[item_name] = true
    end
    return item_name_set
end

function matrix_solver.get_items(subfactory_data)
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local desired_outputs = subfactory_metadata.desired_outputs
    local line_inputs = subfactory_metadata.line_inputs
    local line_outputs = subfactory_metadata.line_outputs
    local all_items = matrix_solver.union_sets(desired_outputs, line_inputs, line_outputs)
    local raw_inputs = matrix_solver.set_diff(line_inputs, line_outputs)
    local by_products = matrix_solver.set_diff(matrix_solver.set_diff(line_outputs, line_inputs), desired_outputs)
    local unproduced_outputs = matrix_solver.set_diff(desired_outputs, line_outputs)
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
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local desired_outputs = subfactory_metadata.desired_outputs
    local line_inputs = subfactory_metadata.line_inputs
    local line_outputs = subfactory_metadata.line_outputs
    local all_items = matrix_solver.union_sets(desired_outputs, line_inputs, line_outputs)
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

    matrix_solver.to_reduced_row_echelon_form(matrix)

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
                Ingredient = line_aggregate.Ingredient,
                Fuel = line_aggregate.Fuel
            }
        end
    end
end

-- finds inputs and outputs for each lines and desired outputs
function matrix_solver.get_subfactory_metadata(subfactory_data)
    local desired_outputs = {}
    for _, product in pairs(subfactory_data.top_level_products) do
        local item_key = matrix_solver.get_item_key(product.proto.type, product.proto.name)
        desired_outputs[item_key] = true
    end

    local line_inputs = {}
    local line_outputs = {}
    for _, line in pairs(subfactory_data.top_floor.lines) do
        line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, 1)
        for item_type_name, item_data in pairs(line_aggregate.Ingredient) do
            for item_name, _ in pairs(item_data) do
                local item_key = matrix_solver.get_item_key(item_type_name, item_name)
                line_inputs[item_key] = true
            end
        end
        for item_type_name, item_data in pairs(line_aggregate.Product) do
            for item_name, _ in pairs(item_data) do
                local item_key = matrix_solver.get_item_key(item_type_name, item_name)
                line_outputs[item_key] = true
            end
        end
    end
    result = {
        desired_outputs = desired_outputs,
        line_inputs = line_inputs,
        line_outputs = line_outputs
    }
    return result
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

            -- use amounts for 1 building as matrix entries
            line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, 1)

            for item_type_name, items in pairs(line_aggregate.Product) do
                for item_name, amount in pairs(items) do
                    local item_key = matrix_solver.get_item_key(item_type_name, item_name)
                    local row_num = rows.map[item_key]
                    matrix[row_num][col_num] = matrix[row_num][col_num] + amount
                end
            end

            for item_type_name, items in pairs(line_aggregate.Ingredient) do
                for item_name, amount in pairs(items) do
                    local item_key = matrix_solver.get_item_key(item_type_name, item_name)
                    local row_num = rows.map[item_key]
                    matrix[row_num][col_num] = matrix[row_num][col_num] - amount
                end
            end
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

function matrix_solver.get_line_aggregate(line_data, player_index, machine_count)
    local line_aggregate = structures.aggregate.init(player_index, 1)
    -- the index in the subfactory_data.top_floor.lines table can be different from the line_id!
    local recipe_proto = line_data.recipe_proto
    local timescale = line_data.timescale
    local amount_per_timescale = machine_count * timescale * line_data.machine_proto.speed / recipe_proto.energy
    structures.aggregate.add(line_aggregate, "Product", recipe_proto.main_product, recipe_proto.main_product.amount * amount_per_timescale)
    for _, product in pairs(recipe_proto.products) do
        structures.aggregate.add(line_aggregate, "Byproduct", product, product.amount * amount_per_timescale)
    end
    for _, ingredient in pairs(recipe_proto.ingredients) do
        structures.aggregate.add(line_aggregate, "Ingredient", ingredient, ingredient.amount * amount_per_timescale)
    end

    local energy_consumption = line_data.machine_proto.energy_usage * machine_count * timescale
    local pollution = line_data.machine_proto.emissions * machine_count * timescale

    line_aggregate.energy_consumption = energy_consumption
    line_aggregate.pollution = pollution

    -- copied from model.lua
    local Fuel = structures.class.init()
    local burner = line_data.machine_proto.burner

    if burner ~= nil and burner.categories["chemical"] then  -- only handles chemical fuels for now
        local fuel_proto = line_data.fuel_proto  -- Lines without subfloors will always have a fuel_proto attached
        local fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, burner,
          fuel_proto.fuel_value, line_data.timescale)

        local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
        structures.class.add(Fuel, fuel)
        structures.aggregate.add(line_aggregate, "Fuel", fuel)

        -- This is to work around the fuel not being detected as a possible product
        structures.aggregate.add(line_aggregate, "Product", fuel)
        structures.aggregate.subtract(line_aggregate, "Ingredient", fuel)

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used
    end

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

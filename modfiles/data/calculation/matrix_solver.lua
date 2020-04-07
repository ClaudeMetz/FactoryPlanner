--[[
Author: Scott Sullivan 2/23/2020
github: scottmsul

Algorithm Overview
------------------
The algorithm is based on the post here: https://kirkmcdonald.github.io/posts/calculation.html
We solve the matrix equation Ax = b, where:
    - A is a matrix whose entry in row i and col j is the output/timescale/building for item i and recipe j (negative is input, positive is output)
    - x is the vector of unknowns that we're solving for, and whose jth entry will be the # buildings needed for recipe j
    - b is the vector whose ith entry is the desired output/timescale for item i
Note the current implementation requires a square matrix.
If there are more recipes than items, the problem is under-constrained and some recipes must be deleted.
If there are more items than recipes, the problem is over-constrained (this is more common).
    In this case we can construct "pseudo-recipes" for certrain items that produce 1/timescale/"building".
    Items with pseudo-recipes will be "free" variables that will have some constrained non-zero input or output after solving.
    The solved "number of buildings" will be equal to the extra input or output needed for that item.
    Typically these pseudo-recipes will be for external inputs or non-fully-recycled byproducts.
Currently the algorithm assumes any item which is part of at least one input and one output in any recipe is not a free variable,
    though the user can click on constrained items in the matrix dialog to make them free variables.
    The dialog calls constrained intermediate items "eliminated" since their output is constrained to zero.
If a recipe has loops, typically the user needs to make voids or free variables.
    Note that currently the factory planner doesn't do anything if a user clicks on byproducts, so at this time it is impossible to make voids.
--]]
matrix_solver = {}

-- for our purposes the string "(item type id)_(item id)" is what we're calling the "item_key"
function matrix_solver.get_item_key(item_type_name, item_name)
    local item_type_id = global.all_items.map[item_type_name]
    local item_id = global.all_items.types[item_type_id].map[item_name]
    return tostring(item_type_id)..'_'..tostring(item_id)
end

function matrix_solver.get_item(item_key)
    local split_str = cutil.split(item_key, "_")
    local item_type_id = split_str[1]
    local item_id = split_str[2]
    return global.all_items.types[item_type_id].items[item_id]
end

-- this is really only used for debugging
function matrix_solver.get_item_name(item_key)
    local split_str = cutil.split(item_key, "_")
    local item_type_id = split_str[1]
    local item_id = split_str[2]
    local item_info = global.all_items.types[item_type_id].items[item_id]
    return item_info.type.."_"..item_info.name
end

function matrix_solver.print_rows(rows)
    matrix_solver.print_items_list(rows.values)
end

function matrix_solver.print_columns(columns)
    for i, k in ipairs(columns.values) do
        local col_split_str = cutil.split(k, "_")
        if col_split_str[1]=="line" then
            llog(k)
        else
            local item_key = col_split_str[2].."_"..col_split_str[3]
            llog(matrix_solver.get_item_name(item_key))
        end
    end
end

function matrix_solver.print_items_set(items)
    item_name_set = {}
    for k, _ in pairs(items) do
        local item_name = matrix_solver.get_item_name(k)
        item_name_set[item_name] = k
    end
    llog(item_name_set)
end

function matrix_solver.print_items_list(items)
    item_name_set = {}
    for _, k in ipairs(items) do
        local item_name = matrix_solver.get_item_name(k)
        item_name_set[item_name] = k
    end
    llog(item_name_set)
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

function matrix_solver.run_matrix_solver(player, subfactory_data, variables, check_linear_dependence)
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local all_items = subfactory_metadata.all_items
    local row_items = matrix_solver.set_diff(all_items, subfactory_metadata.unproduced_outputs)
    local rows = matrix_solver.get_mapping_struct(row_items)

    -- storing the line keys as "line_(lines index 1)_(lines index 2)_..." for arbitrary depths of subfloors
    local function get_line_names(prefix, lines)
        local line_names = {}
        for i, line in ipairs(lines) do
            local line_key = prefix.."_"..i
            -- these are exclusive because only actual recipes are allowed to be inputs to the matrix solver
            if line.subfloor == nil then
                line_names[line_key] = true
            else
                local subfloor_line_names = get_line_names(line_key, line.subfloor.lines)
                line_names = matrix_solver.union_sets(line_names, subfloor_line_names)
            end
        end
        return line_names
    end
    local line_names = get_line_names("line", subfactory_data.top_floor.lines)

    local raw_free_variables = matrix_solver.union_sets(subfactory_metadata.raw_inputs, subfactory_metadata.byproducts)
    local free_variables = {}
    for k, _ in pairs(raw_free_variables) do
        free_variables["item_"..k] = true
    end
    for i, v in ipairs(variables.free) do
        free_variables["item_"..v] = true
    end
    local col_set = matrix_solver.union_sets(line_names, free_variables)
    local columns = matrix_solver.get_mapping_struct(col_set)
    local matrix = matrix_solver.get_matrix(subfactory_data, rows, columns)

    matrix_solver.to_reduced_row_echelon_form(matrix)
    if check_linear_dependence then
        local linearly_dependent_cols = matrix_solver.find_linearly_dependent_cols(matrix)
        local linearly_dependent_variables = {}
        for col, _ in pairs(linearly_dependent_cols) do
            local col_name = columns.values[col]
            local col_split_str = cutil.split(col_name, "_")
            if col_split_str[1] == "line" then
                local floor = subfactory_data.top_floor
                for i=2, #col_split_str-1 do
                    local line_table_id = col_split_str[i]
                    floor = floor.lines[line_table_id].subfloor
                end
                local line_table_id = col_split_str[#col_split_str]
                local line = floor.lines[line_table_id]
                local recipe_id = line.recipe_proto.id
                linearly_dependent_variables["recipe_"..recipe_id] = true
            else -- item
                linearly_dependent_variables[col_name] = true
            end
        end
        return linearly_dependent_variables
    end

    local main_aggregate = structures.aggregate.init(subfactory_data.player_index, 1)

    local function set_line_results(prefix, floor)
        local floor_aggregate = structures.aggregate.init(subfactory_data.player_index, floor.id)
        for i, line in ipairs(floor.lines) do
            local line_key = prefix.."_"..i
            local line_aggregate = nil
            if line.subfloor == nil then
                local col_num = columns.map[line_key]
                local machine_count = matrix[col_num][#columns.values+1] -- want the jth entry in the last column (output of row-reduction)
                line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, floor.id, machine_count, subfactory_metadata)
            else
                line_aggregate = set_line_results(prefix.."_"..i, line.subfloor)
                matrix_solver.consolidate(line_aggregate)
            end

            -- this seems to be how the model sets the machine_count for subfloors - by the machine_count of the subfloor's top line
            if i==1 then floor_aggregate.machine_count = line_aggregate.machine_count end

            structures.aggregate.add_aggregate(line_aggregate, floor_aggregate)

            calculation.interface.set_line_result {
                player_index = player.index,
                floor_id = floor.id,
                line_id = line.id,
                machine_count = line_aggregate.machine_count,
                energy_consumption = line_aggregate.energy_consumption,
                pollution = line_aggregate.pollution,
                production_ratio = 1,
                uncapped_production_ratio = 1,
                Product = line_aggregate.Product,
                Byproduct = line_aggregate.Byproduct,
                Ingredient = line_aggregate.Ingredient,
                Fuel = line_aggregate.Fuel
            }
        end
        return floor_aggregate
    end

    local top_floor_aggregate = set_line_results("line", subfactory_data.top_floor)

    -- set main_aggregate free variables
    for item_line_key, _ in pairs(free_variables) do
        local col_num = columns.map[item_line_key]
        local split_str = cutil.split(item_line_key, "_")
        local item_key = split_str[2].."_"..split_str[3]
        local item = matrix_solver.get_item(item_key)
        local amount = matrix[col_num][#columns.values+1]
        if amount < 0 then
            -- counterintuitively, a negative amount means we have a negative number of "pseudo-buildings",
            -- implying the item must be consumed to balance the matrix, hence it is a byproduct. The opposite is true for ingredients.
            structures.aggregate.add(main_aggregate, "Byproduct", item, -amount)
        else
            structures.aggregate.add(main_aggregate, "Ingredient", item, amount)
        end
    end
    
    -- set products for unproduced items
    for _, product in pairs(subfactory_data.top_level_products) do
        local item_key = matrix_solver.get_item_key(product.proto.type, product.proto.name)
        if subfactory_metadata.unproduced_outputs[item_key] then
            local item = matrix_solver.get_item(item_key)
            structures.aggregate.add(main_aggregate, "Product", item, product.required_amount)
        end
    end

    calculation.interface.set_subfactory_result {
        player_index = subfactory_data.player_index,
        energy_consumption = top_floor_aggregate.energy_consumption,
        pollution = top_floor_aggregate.pollution,
        Product = main_aggregate.Product,
        Byproduct = main_aggregate.Byproduct,
        Ingredient = main_aggregate.Ingredient,
        variables = variables
    }
end

-- If an aggregate has items that are both inputs and outputs, deletes whichever is smaller and saves the net amount.
-- If the input and output are identical to within rounding error, delete from both.
-- This is mainly for calculating line aggregates with subfloors for the matrix solver.
function matrix_solver.consolidate(aggregate)
    -- Items cannot be both products or byproducts, but they can be both ingredients and fuels.
    -- In the case that an item appears as an output, an ingredient, and a fuel, delete from fuel first.
    local function compare_classes(input_class, output_class)
        for type, type_table in pairs(aggregate[output_class]) do
            for item, output_amount in pairs(type_table) do
                item_table = {
                    type=type,
                    name=item
                }
                if aggregate[input_class][type] ~= nil then
                    if aggregate[input_class][type][item] ~= nil then
                        local input_amount = aggregate[input_class][type][item]
                        net_amount = output_amount - input_amount
                        if net_amount > 0 then
                            structures.aggregate.subtract(aggregate, input_class, item_table, input_amount)
                            structures.aggregate.subtract(aggregate, output_class, item_table, input_amount)
                        else
                            structures.aggregate.subtract(aggregate, input_class, item_table, output_amount)
                            structures.aggregate.subtract(aggregate, output_class, item_table, output_amount)
                        end
                    end
                end
            end
        end
    end
    compare_classes("Fuel", "Product")
    compare_classes("Fuel", "Byproduct")
    compare_classes("Ingredient", "Product")
    compare_classes("Ingredient", "Byproduct")
end


-- finds inputs and outputs for each line and desired outputs
function matrix_solver.get_subfactory_metadata(subfactory_data)
    local desired_outputs = {}
    for _, product in pairs(subfactory_data.top_level_products) do
        local item_key = matrix_solver.get_item_key(product.proto.type, product.proto.name)
        desired_outputs[item_key] = true
    end
    local lines_metadata = matrix_solver.get_lines_metadata(subfactory_data.top_floor.lines, subfactory_data.player_index)
    local line_inputs = lines_metadata.line_inputs
    local line_outputs = lines_metadata.line_outputs
    local all_items = matrix_solver.union_sets(desired_outputs, line_inputs, line_outputs)
    local raw_inputs = matrix_solver.set_diff(line_inputs, line_outputs)
    local byproducts = matrix_solver.set_diff(matrix_solver.set_diff(line_outputs, line_inputs), desired_outputs)
    local unproduced_outputs = matrix_solver.set_diff(desired_outputs, line_outputs)
    result = {
        recipes = lines_metadata.line_recipes,
        desired_outputs = desired_outputs,
        all_items = all_items,
        raw_inputs = raw_inputs,
        byproducts = byproducts,
        unproduced_outputs = unproduced_outputs
    }
    return result
end

function matrix_solver.get_lines_metadata(lines, player_index)
    local line_recipes = {}
    local line_inputs = {}
    local line_outputs = {}
    for _, line in pairs(lines) do
        line_aggregate = matrix_solver.get_line_aggregate(line, player_index, 1, 1)
        for item_type_name, item_data in pairs(line_aggregate.Ingredient) do
            for item_name, _ in pairs(item_data) do
                local item_key = matrix_solver.get_item_key(item_type_name, item_name)
                line_inputs[item_key] = true
            end
        end
        for item_type_name, item_data in pairs(line_aggregate.Fuel) do
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
        if line.subfloor ~= nil then
            floor_metadata = matrix_solver.get_lines_metadata(line.subfloor.lines, player_index)
            for i, subfloor_line_recipe in pairs(floor_metadata.line_recipes) do
                table.insert(line_recipes, subfloor_line_recipe)
            end
            line_inputs = matrix_solver.union_sets(line_inputs, floor_metadata.line_inputs)
            line_outputs = matrix_solver.union_sets(line_outputs, floor_metadata.line_outputs)
        else
            table.insert(line_recipes, line.recipe_proto.id)
        end
    end
    return {
        line_recipes = line_recipes,
        line_inputs = line_inputs,
        line_outputs = line_outputs
    }
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
        else -- "line"
            local floor = subfactory_data.top_floor
            for i=2, #col_split_str-1 do
                local line_table_id = col_split_str[i]
                floor = floor.lines[line_table_id].subfloor
            end
            local line_table_id = col_split_str[#col_split_str]
            local line = floor.lines[line_table_id]

            -- use amounts for 1 building as matrix entries
            line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, floor.id, 1)

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

            for item_type_name, items in pairs(line_aggregate.Fuel) do
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
        -- will be nil for unproduced outputs
        if row_num ~= nil then
            local amount = product.required_amount
            matrix[row_num][#columns.values+1] = amount
        end
    end

    return matrix
end

function matrix_solver.get_line_aggregate(line_data, player_index, floor_id, machine_count, subfactory_metadata)
    local line_aggregate = structures.aggregate.init(player_index, floor_id)
    line_aggregate.machine_count = machine_count
    -- the index in the subfactory_data.top_floor.lines table can be different from the line_id!
    local recipe_proto = line_data.recipe_proto
    local timescale = line_data.timescale
    local machine_speed = line_data.machine_proto.speed
    local speed_multiplier = (1 + math.max(line_data.total_effects.speed, -0.8))
    local productivity_multiplier = (1 + math.max(line_data.total_effects.productivity, 0))
    local energy = recipe_proto.energy
    -- hacky workaround for recipes with zero energy - this really messes up the matrix
    if energy==0 then energy=0.000000001 end
    local time_per_craft = energy / (machine_speed * speed_multiplier)
    if recipe_proto.name == "rocket-part" then
        -- extra time for launch sequence
        -- the factorio wiki says 40.33, but I saw this elsewhere in the code (and this agrees with the online factorio calculator). Not sure which is correct.
        time_per_craft = time_per_craft + 41.25/100
    end
    local amount_per_timescale = machine_count * timescale / time_per_craft
    for _, product in pairs(recipe_proto.products) do
        local item_key = matrix_solver.get_item_key(product.type, product.name)
        if subfactory_metadata~= nil and subfactory_metadata.byproducts[item_key] then
            structures.aggregate.add(line_aggregate, "Byproduct", product, product.amount * amount_per_timescale * productivity_multiplier)
        else
            structures.aggregate.add(line_aggregate, "Product", product, product.amount * amount_per_timescale * productivity_multiplier)
        end
    end
    for _, ingredient in pairs(recipe_proto.ingredients) do
        structures.aggregate.add(line_aggregate, "Ingredient", ingredient, ingredient.amount * amount_per_timescale)
    end

    -- some of this is copied from model.lua
    -- Determine energy consumption (including potential fuel needs) and pollution
    local energy_consumption = calculation.util.determine_energy_consumption(line_data.machine_proto,
      machine_count, line_data.total_effects)
    local pollution = calculation.util.determine_pollution(line_data.machine_proto, line_data.recipe_proto,
      line_data.fuel_proto, line_data.total_effects, energy_consumption)

    local Fuel = structures.class.init()
    local burner = line_data.machine_proto.burner

    if burner ~= nil and burner.categories["chemical"] then  -- only handles chemical fuels for now
        local fuel_proto = line_data.fuel_proto  -- Lines without subfloors will always have a fuel_proto attached
        local fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, burner,
          fuel_proto.fuel_value, line_data.timescale)

        local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
        structures.class.add(Fuel, fuel)
        structures.aggregate.add(line_aggregate, "Fuel", fuel)

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used
    end

    line_aggregate.energy_consumption = energy_consumption
    line_aggregate.pollution = pollution

    matrix_solver.consolidate(line_aggregate)

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

function matrix_solver.find_linearly_dependent_cols(matrix)
    local row_index = 1
    local num_rows = #matrix
    local num_cols = #matrix[1]-1
    local ones_map = {}
    local col_set = {}
    for col_index=1, num_cols do
        if matrix[row_index][col_index]==1 then
            ones_map[row_index] = col_index
            row_index = row_index+1
        else
            col_set[col_index] = true
            for i=1, row_index do
                if matrix[i][col_index] ~= 0 then
                    col_set[ones_map[i]] = true
                end
            end
        end
    end
    return col_set
end

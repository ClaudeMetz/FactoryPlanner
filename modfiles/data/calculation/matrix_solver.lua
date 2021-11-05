--[[
Author: Scott Sullivan 2/23/2020
github: scottmsul

Algorithm Overview
------------------
The algorithm is based on the post here: https://kirkmcdonald.github.io/posts/calculation.html
We solve the matrix equation Ax = b, where:
    - A is a matrix whose entry in row i and col j is the output/timescale/building for item i and recipe j
      (negative is input, positive is output)
    - x is the vector of unknowns that we're solving for, and whose jth entry will be the # buildings needed for recipe j
    - b is the vector whose ith entry is the desired output/timescale for item i
Note the current implementation requires a square matrix.
If there are more recipes than items, the problem is under-constrained and some recipes must be deleted.
If there are more items than recipes, the problem is over-constrained (this is more common).
    In this case we can construct "pseudo-recipes" for certrain items that produce 1/timescale/"building".
    Items with pseudo-recipes will be "free" variables that will have some constrained non-zero input or
      output after solving.
    The solved "number of buildings" will be equal to the extra input or output needed for that item.
    Typically these pseudo-recipes will be for external inputs or non-fully-recycled byproducts.
Currently the algorithm assumes any item which is part of at least one input and one output in any recipe
  is not a free variable,
    though the user can click on constrained items in the matrix dialog to make them free variables.
    The dialog calls constrained intermediate items "eliminated" since their output is constrained to zero.
If a recipe has loops, typically the user needs to make voids or free variables.
--]]

matrix_solver = {}

function matrix_solver.get_recipe_protos(recipe_ids)
    local recipe_protos = {}
    for i, recipe_id in ipairs(recipe_ids) do
        local recipe_proto = global.all_recipes.recipes[recipe_id]
        recipe_protos[i] = recipe_proto
    end
    return recipe_protos
end

function matrix_solver.get_item_protos(item_keys)
    local item_protos = {}
    for i, item_key in ipairs(item_keys) do
        local item_proto = matrix_solver.get_item(item_key)
        item_protos[i] = item_proto
    end
    return item_protos
end

-- for our purposes the string "(item type id)_(item id)" is what we're calling the "item_key"
function matrix_solver.get_item_key(item_type_name, item_name)
    local item_type_id = global.all_items.map[item_type_name]
    local item_id = global.all_items.types[item_type_id].map[item_name]
    return tostring(item_type_id)..'_'..tostring(item_id)
end

function matrix_solver.get_item(item_key)
    local split_str = split_string(item_key, "_")
    local item_type_id = split_str[1]
    local item_id = split_str[2]
    return global.all_items.types[item_type_id].items[item_id]
end

-- this is really only used for debugging
function matrix_solver.get_item_name(item_key)
    local split_str = split_string(item_key, "_")
    local item_type_id = split_str[1]
    local item_id = split_str[2]
    local item_info = global.all_items.types[item_type_id].items[item_id]
    return item_info.type.."_"..item_info.name
end

function matrix_solver.print_rows(rows)
    local s = 'ROWS\n'
    for i, k in ipairs(rows.values) do
        local item_name = matrix_solver.get_item_name(k)
        s = s..'ROW '..i..': '..item_name..'\n'
    end
    llog(s)
end

function matrix_solver.print_columns(columns)
    local s = 'COLUMNS\n'
    for i, k in ipairs(columns.values) do
        local col_split_str = split_string(k, "_")
        if col_split_str[1]=="line" then
            s = s..'COL '..i..': '..k..'\n'
        else
            local item_key = col_split_str[2].."_"..col_split_str[3]
            local item_name = matrix_solver.get_item_name(item_key)
            s = s..'COL '..i..': '..item_name..'\n'
        end
    end
    llog(s)
end

function matrix_solver.print_items_set(items)
    local item_name_set = {}
    for k, _ in pairs(items) do
        local item_name = matrix_solver.get_item_name(k)
        item_name_set[item_name] = k
    end
    llog(item_name_set)
end

function matrix_solver.print_items_list(items)
    local item_name_set = {}
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
    for _, set in pairs(arg) do
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
    for _, set in pairs(arg) do
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

function matrix_solver.num_elements(...)
    local arg = {...}
    local count = 0
    for _, set in pairs(arg) do
        for e, _ in pairs(set) do
            count = count + 1
        end
    end
    return count
end

function matrix_solver.get_matrix_solver_metadata(subfactory_data)
    local eliminated_items = {}
    local free_items = {}
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local recipes = subfactory_metadata.recipes
    local all_items = subfactory_metadata.all_items
    local raw_inputs = subfactory_metadata.raw_inputs
    local byproducts = subfactory_metadata.byproducts
    local unproduced_outputs = subfactory_metadata.unproduced_outputs
    local produced_outputs = matrix_solver.set_diff(subfactory_metadata.desired_outputs, unproduced_outputs)
    local free_variables = matrix_solver.union_sets(raw_inputs, byproducts, unproduced_outputs)
    local intermediate_items = matrix_solver.set_diff(all_items, free_variables)
    if subfactory_data.matrix_free_items == nil then
        eliminated_items = intermediate_items
    else
        -- by default when a subfactory is updated, add any new variables to eliminated and let the user select free.
        local free_items_list = subfactory_data.matrix_free_items
        for _, free_item in ipairs(free_items_list) do
            free_items[free_item["identifier"]] = true
        end
        -- make sure that any items that no longer exist are removed
        free_items = matrix_solver.intersect_sets(free_items, intermediate_items)
        eliminated_items = matrix_solver.set_diff(intermediate_items, free_items)
    end
    local num_rows = matrix_solver.num_elements(raw_inputs, byproducts, eliminated_items, free_items)
    local num_cols = matrix_solver.num_elements(recipes, raw_inputs, byproducts, free_items)
    local result = {
        recipes = subfactory_metadata.recipes,
        ingredients = matrix_solver.get_item_protos(matrix_solver.set_to_ordered_list(subfactory_metadata.raw_inputs)),
        products = matrix_solver.get_item_protos(matrix_solver.set_to_ordered_list(produced_outputs)),
        byproducts = matrix_solver.get_item_protos(matrix_solver.set_to_ordered_list(subfactory_metadata.byproducts)),
        eliminated_items = matrix_solver.get_item_protos(matrix_solver.set_to_ordered_list(eliminated_items)),
        free_items = matrix_solver.get_item_protos(matrix_solver.set_to_ordered_list(free_items)),
        num_rows = num_rows,
        num_cols = num_cols
    }
    return result
end

function matrix_solver.transpose(m)
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

function matrix_solver.get_linear_dependence_data(subfactory_data, matrix_metadata)
    local num_rows = matrix_metadata.num_rows
    local num_cols = matrix_metadata.num_cols

    local linearly_dependent_recipes = {}
    local linearly_dependent_items = {}
    local allowed_free_items = {}

    local linearly_dependent_cols = matrix_solver.run_matrix_solver(subfactory_data, true)
    for col_name, _ in pairs(linearly_dependent_cols) do
        local col_split_str = split_string(col_name, "_")
        if col_split_str[1] == "recipe" then
            local recipe_key = col_split_str[2]
            linearly_dependent_recipes[recipe_key] = true
        else -- "item"
            local item_key = col_split_str[2].."_"..col_split_str[3]
            linearly_dependent_items[item_key] = true
        end
    end
    -- check which eliminated items could be made free while still retaining linear independence
    if #linearly_dependent_cols == 0 and num_cols < num_rows then
        local matrix_data = matrix_solver.get_matrix_data(subfactory_data)
        local items = matrix_data.rows
        local col_to_item = {}
        for k, v in pairs(items.map) do
            col_to_item[v] = k
        end

        local t_matrix = matrix_solver.transpose(matrix_data.matrix)
        table.remove(t_matrix)
        matrix_solver.to_reduced_row_echelon_form(t_matrix)
        local t_linearly_dependent = matrix_solver.find_linearly_dependent_cols(t_matrix, false)

        local eliminated_items = matrix_metadata.eliminated_items
        local eliminated_keys = {}
        for _, eliminated_item in ipairs(eliminated_items) do
            local key = matrix_solver.get_item_key(eliminated_item.type, eliminated_item.name)
            eliminated_keys[key] = eliminated_item
        end

        for col, _ in pairs(t_linearly_dependent) do
            local item = col_to_item[col]
            if eliminated_keys[item] then
                allowed_free_items[item] = true
            end
        end
    end
    local result = {
        linearly_dependent_recipes = matrix_solver.get_recipe_protos(
            matrix_solver.set_to_ordered_list(linearly_dependent_recipes)),
        linearly_dependent_items = matrix_solver.get_item_protos(
            matrix_solver.set_to_ordered_list(linearly_dependent_items)),
        allowed_free_items = matrix_solver.get_item_protos(
            matrix_solver.set_to_ordered_list(allowed_free_items))
    }
    return result
end

function matrix_solver.get_matrix_data(subfactory_data)
    local matrix_metadata = matrix_solver.get_matrix_solver_metadata(subfactory_data)
    local matrix_free_items = matrix_metadata.free_items

    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local all_items = subfactory_metadata.all_items
    local rows = matrix_solver.get_mapping_struct(all_items)

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
    for _, v in ipairs(matrix_free_items) do
        local item_key = matrix_solver.get_item_key(v.type, v.name)
        free_variables["item_"..item_key] = true
    end
    local col_set = matrix_solver.union_sets(line_names, free_variables)
    local columns = matrix_solver.get_mapping_struct(col_set)
    local matrix = matrix_solver.get_matrix(subfactory_data, rows, columns)

    return {
        matrix = matrix,
        rows = rows,
        columns = columns,
        free_variables = free_variables,
        matrix_free_items = matrix_free_items,
    }
end

function matrix_solver.run_matrix_solver(subfactory_data, check_linear_dependence)
    -- run through get_matrix_solver_metadata to check against recipe changes
    local subfactory_metadata = matrix_solver.get_subfactory_metadata(subfactory_data)
    local matrix_data = matrix_solver.get_matrix_data(subfactory_data)
    local matrix = matrix_data.matrix
    local columns = matrix_data.columns
    local free_variables = matrix_data.free_variables
    local matrix_free_items = matrix_data.matrix_free_items

    matrix_solver.to_reduced_row_echelon_form(matrix)
    if check_linear_dependence then
        local linearly_dependent_cols = matrix_solver.find_linearly_dependent_cols(matrix, true)
        local linearly_dependent_variables = {}
        for col, _ in pairs(linearly_dependent_cols) do
            local col_name = columns.values[col]
            local col_split_str = split_string(col_name, "_")
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

    local function set_line_results(prefix, floor)
        local floor_aggregate = structures.aggregate.init(subfactory_data.player_index, floor.id)
        for i, line in ipairs(floor.lines) do
            local line_key = prefix.."_"..i
            local line_aggregate = nil
            if line.subfloor == nil then
                local col_num = columns.map[line_key]
                 -- want the j-th entry in the last column (output of row-reduction)
                local machine_count = matrix[col_num][#columns.values+1]
                line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index, floor.id,
                  machine_count, false, subfactory_metadata, free_variables)
            else
                line_aggregate = set_line_results(prefix.."_"..i, line.subfloor)
                matrix_solver.consolidate(line_aggregate)
            end

            -- lines with subfloors should show actual number of machines to build, so each machine count is rounded up when summed
            floor_aggregate.machine_count = floor_aggregate.machine_count + math.ceil(line_aggregate.machine_count)

            structures.aggregate.add_aggregate(line_aggregate, floor_aggregate)

            calculation.interface.set_line_result{
                player_index = subfactory_data.player_index,
                floor_id = floor.id,
                line_id = line.id,
                machine_count = line_aggregate.machine_count,
                energy_consumption = line_aggregate.energy_consumption,
                pollution = line_aggregate.pollution,
                production_ratio = line_aggregate.production_ratio,
                uncapped_production_ratio = line_aggregate.uncapped_production_ratio,
                Product = line_aggregate.Product,
                Byproduct = line_aggregate.Byproduct,
                Ingredient = line_aggregate.Ingredient,
                fuel_amount = line_aggregate.fuel_amount
            }
        end
        return floor_aggregate
    end

    local top_floor_aggregate = set_line_results("line", subfactory_data.top_floor)

    local main_aggregate = structures.aggregate.init(subfactory_data.player_index, 1)

    -- set main_aggregate free variables
    for item_line_key, _ in pairs(free_variables) do
        local col_num = columns.map[item_line_key]
        local split_str = split_string(item_line_key, "_")
        local item_key = split_str[2].."_"..split_str[3]
        local item = matrix_solver.get_item(item_key)
        local amount = matrix[col_num][#columns.values+1]
        if amount < 0 then
            -- counterintuitively, a negative amount means we have a negative number of "pseudo-buildings",
            -- implying the item must be consumed to balance the matrix, hence it is a byproduct.
            -- The opposite is true for ingredients.
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
            structures.aggregate.add(main_aggregate, "Product", item, product.amount)
        end
    end

    calculation.interface.set_subfactory_result {
        player_index = subfactory_data.player_index,
        energy_consumption = top_floor_aggregate.energy_consumption,
        pollution = top_floor_aggregate.pollution,
        Product = main_aggregate.Product,
        Byproduct = main_aggregate.Byproduct,
        Ingredient = main_aggregate.Ingredient,
        matrix_free_items = matrix_free_items
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
                local item_table = {
                    type=type,
                    name=item
                }
                if aggregate[input_class][type] ~= nil then
                    if aggregate[input_class][type][item] ~= nil then
                        local input_amount = aggregate[input_class][type][item]
                        local net_amount = output_amount - input_amount
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
    local lines_metadata = matrix_solver.get_lines_metadata(subfactory_data.top_floor.lines,
      subfactory_data.player_index)
    local line_inputs = lines_metadata.line_inputs
    local line_outputs = lines_metadata.line_outputs
    local unproduced_outputs = matrix_solver.set_diff(desired_outputs, line_outputs)
    local all_items = matrix_solver.union_sets(line_inputs, line_outputs)
    local raw_inputs = matrix_solver.set_diff(line_inputs, line_outputs)
    local byproducts = matrix_solver.set_diff(matrix_solver.set_diff(line_outputs, line_inputs), desired_outputs)
    return {
        recipes = lines_metadata.line_recipes,
        desired_outputs = desired_outputs,
        all_items = all_items,
        raw_inputs = raw_inputs,
        byproducts = byproducts,
        unproduced_outputs = unproduced_outputs
    }
end

function matrix_solver.get_lines_metadata(lines, player_index)
    local line_recipes = {}
    local line_inputs = {}
    local line_outputs = {}
    for _, line in pairs(lines) do
        if line.subfloor ~= nil then
            local floor_metadata = matrix_solver.get_lines_metadata(line.subfloor.lines, player_index)
            for _, subfloor_line_recipe in pairs(floor_metadata.line_recipes) do
                table.insert(line_recipes, subfloor_line_recipe)
            end
            line_inputs = matrix_solver.union_sets(line_inputs, floor_metadata.line_inputs)
            line_outputs = matrix_solver.union_sets(line_outputs, floor_metadata.line_outputs)
        else
            local line_aggregate = matrix_solver.get_line_aggregate(line, player_index, 1, 1, true)
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
        local col_split_str = split_string(col_str, "_")
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
            local line_aggregate = matrix_solver.get_line_aggregate(line, subfactory_data.player_index,
              floor.id, 1, true)

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

    -- final column for desired output. Don't have to explicitly set constrained vars to zero
    -- since matrix is initialized with zeros.
    for _, product in ipairs(subfactory_data.top_level_products) do
        local item_id = product.proto.identifier
        local row_num = rows.map[item_id]
        -- will be nil for unproduced outputs
        if row_num ~= nil then
            local amount = product.amount
            matrix[row_num][#columns.values+1] = amount
        end
    end

    return matrix
end

function matrix_solver.get_line_aggregate(line_data, player_index, floor_id, machine_count, include_fuel_ingredient, subfactory_metadata, free_variables)
    local line_aggregate = structures.aggregate.init(player_index, floor_id)
    line_aggregate.machine_count = machine_count
    -- the index in the subfactory_data.top_floor.lines table can be different from the line_id!
    local recipe_proto = line_data.recipe_proto
    local timescale = line_data.timescale
    local total_effects = line_data.total_effects
    local machine_speed = line_data.machine_proto.speed
    local speed_multiplier = (1 + math.max(line_data.total_effects.speed, -0.8))
    local energy = recipe_proto.energy
    -- hacky workaround for recipes with zero energy - this really messes up the matrix
    if energy==0 then energy=0.000000001 end
    local time_per_craft = energy / (machine_speed * speed_multiplier)
    local launch_sequence_time = line_data.machine_proto.launch_sequence_time
    if launch_sequence_time then
        time_per_craft = time_per_craft + launch_sequence_time
    end
    local unmodified_crafts_per_second = 1 / time_per_craft
    local in_game_crafts_per_second = math.min(unmodified_crafts_per_second, 60)
    local total_crafts_per_timescale = timescale * machine_count * in_game_crafts_per_second
    line_aggregate.production_ratio = total_crafts_per_timescale
    line_aggregate.uncapped_production_ratio = total_crafts_per_timescale
    for _, product in pairs(recipe_proto.products) do
        local prodded_amount = calculation.util.determine_prodded_amount(product, unmodified_crafts_per_second, total_effects)
        local item_key = matrix_solver.get_item_key(product.type, product.name)
        if subfactory_metadata~= nil and (subfactory_metadata.byproducts[item_key] or free_variables["item_"..item_key]) then
            structures.aggregate.add(line_aggregate, "Byproduct", product, prodded_amount * total_crafts_per_timescale)
        else
            structures.aggregate.add(line_aggregate, "Product", product, prodded_amount * total_crafts_per_timescale)
        end
    end
    for _, ingredient in pairs(recipe_proto.ingredients) do
        local amount = ingredient.amount
        if ingredient.ignore_productivity then
            amount = calculation.util.determine_prodded_amount(ingredient, unmodified_crafts_per_second, total_effects)
        end
        structures.aggregate.add(line_aggregate, "Ingredient", ingredient, amount * total_crafts_per_timescale)
    end

    -- Determine energy consumption (including potential fuel needs) and pollution
    local fuel_proto = line_data.fuel_proto
    local energy_consumption = calculation.util.determine_energy_consumption(line_data.machine_proto,
      machine_count, line_data.total_effects)
    local pollution = calculation.util.determine_pollution(line_data.machine_proto, line_data.recipe_proto,
      line_data.fuel_proto, line_data.total_effects, energy_consumption)

    local fuel_amount = nil
    if fuel_proto ~= nil then  -- Seeing a fuel_proto here means it needs to be re-calculated
        fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, line_data.machine_proto.burner,
          line_data.fuel_proto.fuel_value, timescale)

        if include_fuel_ingredient then
            local fuel = {type=fuel_proto.type, name=fuel_proto.name, amount=fuel_amount}
            structures.aggregate.add(line_aggregate, "Ingredient", fuel, fuel_amount)
        end

        energy_consumption = 0  -- set electrical consumption to 0 when fuel is used

    elseif line_data.machine_proto.energy_type == "void" then
        energy_consumption = 0  -- set electrical consumption to 0 while still polluting
    end

    line_aggregate.energy_consumption = energy_consumption
    line_aggregate.pollution = pollution

    matrix_solver.consolidate(line_aggregate)

    -- needed for calculation.interface.set_line_result
    line_aggregate.fuel_amount = fuel_amount

    return line_aggregate
end

function matrix_solver.print_matrix(m)
    local s = ""
    s = s.."{\n"
    for _, row in ipairs(m) do
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
-- Based on the algorithm from octave: https://fossies.org/dox/FreeMat-4.2-Source/rref_8m_source.html
function matrix_solver.to_reduced_row_echelon_form(m)
    local num_rows = #m
    if #m==0 then return m end
    local num_cols = #m[1]

    -- set tolerance based on max value in matrix
    local max_value = 0
    for i = 1, num_rows do
        for j = 1, num_cols do
            if math.abs(m[i][j]) > max_value then
                max_value = math.abs(m[i][j])
            end
        end
    end
    local tolerance = 1e-10 * max_value

    local pivot_row = 1

    for curr_col = 1, num_cols do
        -- find row with highest value in curr col as next pivot
        local max_pivot_index = pivot_row
        local max_pivot_value = m[pivot_row][curr_col]
        for curr_row = pivot_row+1, num_rows do -- does this need an if-wrapper?
            local curr_pivot_value = math.abs(m[curr_row][curr_col])
            if math.abs(m[curr_row][curr_col]) > math.abs(max_pivot_value) then
                max_pivot_index = curr_row
                max_pivot_value = curr_pivot_value
            end
        end

        if math.abs(max_pivot_value) < tolerance then
            -- if highest value is approximately zero, set this row and all rows below to zero
            for zero_row = pivot_row, num_rows do
                m[zero_row][curr_col] = 0
            end
        else
            -- swap current row with highest value row
            for swap_col = curr_col, num_cols do
                local temp = m[pivot_row][swap_col]
                m[pivot_row][swap_col] = m[max_pivot_index][swap_col]
                m[max_pivot_index][swap_col] = temp
            end

            -- normalize pivot row
            local factor = m[pivot_row][curr_col]
            for normalize_col = curr_col, num_cols do
                m[pivot_row][normalize_col] = m[pivot_row][normalize_col] / factor
            end

            -- eliminate current column from other rows
            for update_row = 1, pivot_row - 1 do
                for update_col = curr_col+1, num_cols do
                    m[update_row][update_col] = m[update_row][update_col] - m[update_row][curr_col]*m[pivot_row][update_col]
                end
                m[update_row][curr_col] = 0
            end
            for update_row = pivot_row+1, num_rows do
                for update_col = curr_col+1, num_cols do
                    m[update_row][update_col] = m[update_row][update_col] - m[update_row][curr_col]*m[pivot_row][update_col]
                end
                m[update_row][curr_col] = 0
            end

            -- only add 1 if there is another leading 1 row
            pivot_row = pivot_row + 1

            if pivot_row > num_rows then
                break
            end
        end
    end
end

function matrix_solver.find_linearly_dependent_cols(matrix, ignore_last)
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
    local ones_map = {}
    local col_set = {}
    for col_index=1, num_cols do
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

-- utility function that removes from a sorted array in place
function matrix_solver.remove(orig_table, value)
    local i = 1
    local found = false
    while i<=#orig_table and (not found) do
        local curr = orig_table[i]
        if curr >= value then
            found = true
        end
        if curr == value then
            table.remove(orig_table, i)
        end
        i = i+1
    end
end

-- utility function that inserts into a sorted array in place
function matrix_solver.insert(orig_table, value)
    local i = 1
    local found = false
    while i<=#orig_table and (not found) do
        local curr = orig_table[i]
        if curr >= value then
            found=true
        end
        if curr > value then
            table.insert(orig_table, i, value)
        end
        i = i+1
    end
    if not found then
        table.insert(orig_table, value)
    end
end

-- Shallowly and naively copys the base level of the given table
function matrix_solver.shallowcopy(table)
    local copy = {}
    for key, value in pairs(table) do
        copy[key] = value
    end
    return copy
end

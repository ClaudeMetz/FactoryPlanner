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

local matrix_engine = {}


---@param recipe_set table<integer, true>
function matrix_engine.get_recipe_protos(recipe_set)
    local recipe_protos = {}
    for recipe_id, _ in pairs(recipe_set) do
        local recipe_proto = prototyper.util.find("recipes", recipe_id, nil)
        table.insert(recipe_protos, recipe_proto)
    end
    return recipe_protos
end

---@param item_set SolverSet
---@return FPItemPrototype[]
function matrix_engine.get_item_protos(item_set)
    local item_protos = {}  ---@type FPItemPrototype[]
    for item_key, _ in pairs(item_set) do
        local item = structures.unpack_item(item_key)
        local item_proto = prototyper.util.find("items", item.name, item.type)  ---@as FPItemPrototype
        table.insert(item_protos, item_proto)
    end
    return item_protos
end


---@class MatrixMetadata
---@field recipes integer[]
---@field ingredients SolverSet
---@field products SolverSet
---@field byproducts SolverSet
---@field eliminated_items SolverSet
---@field free_items SolverSet
---@field num_rows integer
---@field num_cols integer

---@param factory_data FactoryData
---@return MatrixMetadata
function matrix_engine.get_matrix_solver_metadata(factory_data)
    local eliminated_items = {}  ---@type SolverSet
    local free_items = {}  ---@type SolverSet
    local factory_metadata = matrix_engine.get_factory_metadata(factory_data)
    local recipes = factory_metadata.recipes
    local all_items = factory_metadata.all_items
    local raw_inputs = factory_metadata.raw_inputs
    local byproducts = factory_metadata.byproducts
    local unproduced_outputs = factory_metadata.unproduced_outputs
    local produced_outputs = solver.util.set.difference(factory_metadata.desired_outputs, unproduced_outputs)
    local free_variables = solver.util.set.union(raw_inputs, byproducts, unproduced_outputs)
    local intermediate_items = solver.util.set.difference(all_items, free_variables)

    -- by default when a factory is updated, add any new variables to eliminated and let the user select free.
    local free_items_list = factory_data.matrix_free_items
    for _, free_item in ipairs(free_items_list) do
        local item_key = structures.pack_item(free_item)
        free_items[item_key] = true
    end
    -- make sure that any items that no longer exist are removed
    free_items = solver.util.set.intersection(free_items, intermediate_items)  ---@type table<SolverItemKey, true>
    eliminated_items = solver.util.set.difference(intermediate_items, free_items)

    local num_rows = solver.util.set.count(raw_inputs, byproducts, eliminated_items, free_items)
    local num_cols = solver.util.set.count(recipes, raw_inputs, byproducts, free_items)
    local result = {
        recipes = recipes,
        ingredients = raw_inputs,
        products = produced_outputs,
        byproducts = byproducts,
        eliminated_items = eliminated_items,
        free_items = free_items,
        num_rows = num_rows,
        num_cols = num_cols
    }  ---@type MatrixMetadata
    return result
end

---@param m number[][]
---@return number[][]
function matrix_engine.transpose(m)
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

---@class LinearDependanceData
---@field linearly_dependent_recipes FPRecipePrototype[]
---@field linearly_dependent_free_items FPItemPrototype[]
---@field allowed_free_items FPItemPrototype[]

---@param factory_data FactoryData
---@param matrix_metadata MatrixMetadata
---@return LinearDependanceData
function matrix_engine.get_linear_dependence_data(factory_data, matrix_metadata)
    local num_rows = matrix_metadata.num_rows
    local num_cols = matrix_metadata.num_cols

    local linearly_dependent_recipes = {}  ---@type table<integer, true>
    local linearly_dependent_free_items = {}  ---@type SolverSet
    local allowed_free_items = {}  ---@type SolverSet

    local linearly_dependent_cols = matrix_engine.run_matrix_solver(factory_data, true)
    ---@cast linearly_dependent_cols -nil
    if next(linearly_dependent_cols) ~= nil then
        local free_items = matrix_metadata.free_items

        for col_name, _ in pairs(linearly_dependent_cols) do
            local col_split_str = lib.split_string(col_name, "_")
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
    if next(linearly_dependent_cols) == nil and num_cols < num_rows then
        local matrix_data = matrix_engine.get_matrix_data(factory_data)
        local items = matrix_data.rows  -- when transposed becomes columns

        local t_matrix = matrix_engine.transpose(matrix_data.matrix)
        table.remove(t_matrix)
        matrix_engine.to_reduced_row_echelon_form(t_matrix)
        local t_linearly_dependent = matrix_engine.find_linearly_dependent_cols(t_matrix, false)
        local eliminated_items = matrix_metadata.eliminated_items

        for col, _ in pairs(t_linearly_dependent) do  ---@cast col integer
            local item = items.values[col]  ---@as SolverItemKey
            if eliminated_items[item] then allowed_free_items[item] = true end
        end
    end

    local result = {
        linearly_dependent_recipes = matrix_engine.get_recipe_protos(linearly_dependent_recipes),
        linearly_dependent_free_items = matrix_engine.get_item_protos(linearly_dependent_free_items),
        allowed_free_items = matrix_engine.get_item_protos(allowed_free_items)
    }  ---@type LinearDependanceData
    return result
end

---@class MatrixData
---@field matrix number[][]
---@field rows MappingStruct
---@field columns MappingStruct
---@field free_variables table<string, true>
---@field matrix_free_items SolverSet
---@field free_variable_scale_factors number[]

---@param factory_data FactoryData
---@return MatrixData
function matrix_engine.get_matrix_data(factory_data)
    local matrix_metadata = matrix_engine.get_matrix_solver_metadata(factory_data)
    local matrix_free_items = matrix_metadata.free_items

    local factory_metadata = matrix_engine.get_factory_metadata(factory_data)
    local all_items = factory_metadata.all_items
    local rows = matrix_engine.get_mapping_struct(all_items)

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
                line_names = solver.util.set.union(line_names, subfloor_line_names)
            end
        end
        return line_names
    end
    local line_names = get_line_names("line", factory_data.top_floor.lines)

    local raw_free_variables = solver.util.set.union(factory_metadata.raw_inputs, factory_metadata.byproducts)  ---@as SolverSet
    local free_variables = {}  ---@type table<string, true>
    for key, _ in pairs(raw_free_variables) do free_variables["item_" .. key] = true end
    for key, _ in pairs(matrix_free_items) do free_variables["item_" .. key] = true end
    local col_set = solver.util.set.union(line_names, free_variables)
    local columns = matrix_engine.get_mapping_struct(col_set)
    local matrix, free_variable_scale_factors = matrix_engine.get_matrix(factory_data, rows, columns)

    return {
        matrix = matrix,
        rows = rows,
        columns = columns,
        free_variables = free_variables,
        matrix_free_items = matrix_free_items,
        free_variable_scale_factors = free_variable_scale_factors
    }  ---@type MatrixData
end

---@param factory_data FactoryData
---@param check_linear_dependence boolean
---@return table<string, true>?
function matrix_engine.run_matrix_solver(factory_data, check_linear_dependence)
    -- run through get_matrix_solver_metadata to check against recipe changes
    local factory_metadata = matrix_engine.get_factory_metadata(factory_data)
    local matrix_data = matrix_engine.get_matrix_data(factory_data)
    local matrix = matrix_data.matrix
    local columns = matrix_data.columns
    local free_variables = matrix_data.free_variables
    local matrix_free_items = matrix_data.matrix_free_items
    local free_variable_scale_factors = matrix_data.free_variable_scale_factors

    matrix_engine.to_reduced_row_echelon_form(matrix)
    if check_linear_dependence then
        local linearly_dependent_cols = matrix_engine.find_linearly_dependent_cols(matrix, true)
        local linearly_dependent_variables = {}  ---@type table<string, true>
        for col, _ in pairs(linearly_dependent_cols) do  ---@cast col integer
            local col_name = columns.values[col]  ---@as string
            local col_split_str = lib.split_string(col_name, "_")
            if col_split_str[1] == "line" then
                local floor = factory_data.top_floor
                for i=2, #col_split_str-1 do
                    local line_table_id = col_split_str[i]  ---@as integer
                    floor = floor.lines[line_table_id]--[[@cast -nil]].subfloor  ---@as FloorData
                end
                local line_table_id = col_split_str[#col_split_str]  ---@as integer
                local line = floor.lines[line_table_id]  ---@as LineData
                local recipe_id = line.recipe_proto.id
                linearly_dependent_variables["recipe_"..recipe_id] = true
            else -- item
                linearly_dependent_variables[col_name] = true
            end
        end
        return linearly_dependent_variables
    end

    -- rescale ouput column based on free variable scale factors
    for idx, scale_factor in pairs(free_variable_scale_factors) do
        ---@diagnostic disable: need-check-nil
        matrix[idx][#columns.values+1] = matrix[idx][#columns.values+1] * scale_factor
    end

    ---@param prefix string
    ---@param floor FloorData
    local function set_line_results(prefix, floor)
        local floor_aggregate = structures.aggregate.init(floor.id)
        for i, line in ipairs(floor.lines) do
            local line_key = prefix.."_"..i
            local line_aggregate = nil
            if line.subfloor == nil then  ---@cast line LineData
                local col_num = columns.map[line_key]
                 -- want the j-th entry in the last column (output of row-reduction)
                local machine_amount = matrix[col_num]--[[@cast -nil]][#columns.values+1]  ---@as number
                if machine_amount < 0 then machine_amount = 0 end
                line_aggregate = matrix_engine.get_line_aggregate(line, floor.id,
                    machine_amount, factory_metadata, free_variables)
            else
                line_aggregate = set_line_results(prefix.."_"..i, line.subfloor)
                matrix_engine.consolidate(line_aggregate)
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
            if line_aggregate.fuel then
                structures.map.subtract(line_aggregate.ingredients, line_aggregate.fuel, line_aggregate.fuel_amount)
            end

            -- need to call consolidate before set_line_result to net any non-fuel catalysts for display
            matrix_engine.consolidate(line_aggregate)

            solver.set_line_result {
                floor_id = floor.id,
                line_id = line.id,
                machine_amount = line_aggregate.machine_amount,
                production_ratio = line_aggregate.production_ratio,
                products = line_aggregate.products,
                byproducts = line_aggregate.byproducts,
                ingredients = line_aggregate.ingredients,
                fuel_amount = line_aggregate.fuel_amount
            }
        end
        return floor_aggregate
    end

    local top_floor_aggregate = set_line_results("line", factory_data.top_floor)

    -- Nets out items that are produced and consumed in equal amounts across the whole factory,
    -- while the amounts on both sides are still around to tell solver noise from a real leftover
    matrix_engine.consolidate(top_floor_aggregate)

    local total = {}
    for _, item in ipairs(structures.map.list(top_floor_aggregate.products)) do
        structures.map.add(total, item)
    end
    for _, item in ipairs(structures.map.list(top_floor_aggregate.byproducts)) do
        structures.map.add(total, item)
    end
    for _, item in ipairs(structures.map.list(top_floor_aggregate.ingredients)) do
        structures.map.subtract(total, item)
    end

    local required_amount = {}
    for _, product in pairs(factory_data.top_floor.products) do
        local key = structures.pack_item(product)
        required_amount[key] = product.amount
    end

    local main_aggregate = structures.aggregate.init(1)
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
    for _, product in pairs(factory_data.top_floor.products) do
        local item_key = structures.pack_item(product)
        if not factory_metadata.unproduced_outputs[item_key] then
            structures.map.add(main_aggregate.products, product)
        end
    end

    solver.set_factory_result {
        player_index = factory_data.player_index,
        factory_id = factory_data.factory_id,
        products = main_aggregate.products,
        byproducts = main_aggregate.byproducts,
        ingredients = main_aggregate.ingredients,
        matrix_free_items = matrix_engine.get_item_protos(matrix_free_items)
    }
end

-- If an aggregate has items that are both inputs and outputs, deletes whichever is smaller and saves the net amount.
-- If the input and output are identical to within rounding error, delete from both.
-- This is mainly for calculating line aggregates with subfloors for the matrix solver.
---@param aggregate SolverAggregateWithFuel
function matrix_engine.consolidate(aggregate)
    -- Items cannot be both products or byproducts, but they can be both ingredients and fuels.
    -- In the case that an item appears as an output, an ingredient, and a fuel, delete from fuel first.
    ---@param input_map "products" | "byproducts" | "ingredients"
    ---@param output_map "products" | "byproducts" | "ingredients"
    local function compare_maps(input_map, output_map)
        for item_key, output_amount in pairs(aggregate[output_map]) do
            local output_item = structures.unpack_item(item_key, output_amount)
            local input_amount = aggregate[input_map][item_key] or 0
            local net_amount = output_amount - input_amount

            -- Solving leaves a relative error behind, so the leftover of an item that actually
            -- cancels out is proportional to how much of it flows. A fixed margin can't catch
            -- that across amounts as far apart as items and power, so this scales with the flow.
            local scale = math.max(math.abs(output_amount), math.abs(input_amount))
            local cancels_out = math.abs(net_amount) < scale * MAGIC_NUMBERS.margin_of_error

            if cancels_out then  -- take both sides down to nothing, rather than leaving the rest
                structures.map.subtract(aggregate[input_map], output_item, input_amount)
                structures.map.subtract(aggregate[output_map], output_item)
            elseif net_amount > 0 then
                structures.map.subtract(aggregate[input_map], output_item, input_amount)
                structures.map.subtract(aggregate[output_map], output_item, input_amount)
            else
                structures.map.subtract(aggregate[input_map], output_item)
                structures.map.subtract(aggregate[output_map], output_item)
            end
        end
    end
    compare_maps("ingredients", "products")
    compare_maps("ingredients", "byproducts")
end

---@class FactoryMetadata
---@field recipes integer[]
---@field desired_outputs table<SolverItemKey, true>
---@field all_items table<SolverItemKey, true>
---@field raw_inputs table<SolverItemKey, true>
---@field byproducts table<SolverItemKey, true>
---@field unproduced_outputs table<SolverItemKey, true>

-- finds inputs and outputs for each line and desired outputs
---@param factory_data FactoryData
---@return FactoryMetadata
function matrix_engine.get_factory_metadata(factory_data)
    local desired_outputs = {}
    for _, product in pairs(factory_data.top_floor.products) do
        local item_key = structures.pack_item(product)
        desired_outputs[item_key] = true
    end
    local lines_metadata = matrix_engine.get_lines_metadata(factory_data.top_floor.lines)
    local line_inputs = lines_metadata.line_inputs
    local line_outputs = lines_metadata.line_outputs
    local unproduced_outputs = solver.util.set.difference(desired_outputs, line_outputs)
    local all_items = solver.util.set.union(line_inputs, line_outputs)
    local raw_inputs = solver.util.set.difference(line_inputs, line_outputs)
    local byproducts = solver.util.set.difference(solver.util.set.difference(line_outputs, line_inputs), desired_outputs)
    return {
        recipes = lines_metadata.line_recipes,
        desired_outputs = desired_outputs,
        all_items = all_items,
        raw_inputs = raw_inputs,
        byproducts = byproducts,
        unproduced_outputs = unproduced_outputs
    }  ---@type FactoryMetadata
end

---@class MatrixLineMetadata
---@field line_recipes integer[] recipe_ids
---@field line_inputs table<SolverItemKey, true>
---@field line_outputs table<SolverItemKey, true>

---@param lines (LineData | SubfloorLineData)[]
---@return MatrixLineMetadata
function matrix_engine.get_lines_metadata(lines)
    local line_recipes = {}
    local line_inputs = {}
    local line_outputs = {}
    for _, line in pairs(lines) do
        if line.subfloor ~= nil then  ---@cast line SubfloorLineData
            local floor_metadata = matrix_engine.get_lines_metadata(line.subfloor.lines)
            for _, subfloor_line_recipe in pairs(floor_metadata.line_recipes) do
                table.insert(line_recipes, subfloor_line_recipe)
            end
            line_inputs = solver.util.set.union(line_inputs, floor_metadata.line_inputs)
            line_outputs = solver.util.set.union(line_outputs, floor_metadata.line_outputs)
        else  ---@cast line LineData
            local line_aggregate = matrix_engine.get_line_aggregate(line, 1, 1)
            matrix_engine.consolidate(line_aggregate)
            for item_key, _ in pairs(line_aggregate.ingredients) do line_inputs[item_key] = true end
            for item_key, _ in  pairs(line_aggregate.products) do line_outputs[item_key] = true end
            table.insert(line_recipes, line.recipe_proto.id)
        end
    end
    return {
        line_recipes = line_recipes,
        line_inputs = line_inputs,
        line_outputs = line_outputs
    }
end

---@param factory_data FactoryData
---@param rows MappingStruct
---@param columns MappingStruct
---@return number[][]
---@return number[]
function matrix_engine.get_matrix(factory_data, rows, columns)
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

    -- Power that lines draw regardless of their machine count, collected to be demanded below
    local electric_power = {type="entity", name="custom-electric-power", amount=0}  ---@type SolverItem
    local constant_demand = 0.0

    -- loop over columns since it's easier to look up items for lines/free vars than vice-versa
    for col_num=1, #columns.values do
        local col_str = columns.values[col_num]
        local col_split_str = lib.split_string(col_str, "_")
        local col_type = col_split_str[1]
        -- note this string "item" is an internal matrix-solver convention and is unrelated to item types
        if col_type == "item" then
            local item_key = col_split_str[2]  ---@as SolverItemKey
            local row_num = rows.map[item_key]
            matrix[row_num]--[[@cast -nil]][col_num] = 1
        else -- "line"
            local floor = factory_data.top_floor
            for i=2, #col_split_str-1 do
                local line_table_id = col_split_str[i]  ---@as integer
                floor = floor.lines[line_table_id]--[[@cast -nil]].subfloor  ---@as FloorData
            end
            local line_table_id = col_split_str[#col_split_str]  ---@as integer
            local line = floor.lines[line_table_id]  ---@as LineData

            -- use amounts for 1 building as matrix entries
            local line_aggregate = matrix_engine.get_line_aggregate(line,
                floor.id, 1)

            -- Beacons draw the same power however many machines the line ends up needing, so that
            -- part of it can't be expressed per building. It only depends on how the line is
            -- configured though, so it's known upfront and can be demanded of the factory directly.
            if line.beacon_power and line.beacon_power > 0 then
                structures.map.subtract(line_aggregate.ingredients, electric_power, line.beacon_power)
                constant_demand = constant_demand + line.beacon_power
            end

            matrix_engine.consolidate(line_aggregate)

            for item_key, amount in pairs(line_aggregate.products) do
                ---@diagnostic disable: need-check-nil
                local row_num = rows.map[item_key]
                matrix[row_num][col_num] = matrix[row_num][col_num] + amount
            end

            for item_key, amount in pairs(line_aggregate.ingredients) do
                ---@diagnostic disable: need-check-nil
                local row_num = rows.map[item_key]
                matrix[row_num][col_num] = matrix[row_num][col_num] - amount
            end
        end
    end

    -- final column for desired output. Don't have to explicitly set constrained vars to zero
    -- since matrix is initialized with zeros.
    for _, product in ipairs(factory_data.top_floor.products) do
        local item_key = structures.pack_item(product)
        local row_num = rows.map[item_key]  -- will be nil for unproduced outputs
        if row_num ~= nil then
            local amount = product.amount
            matrix[row_num]--[[@cast -nil]][#columns.values+1] = amount
        end
    end

    -- The power taken out of the lines above still needs to come from somewhere, so ask the
    -- factory to produce that much on top of whatever its machines use
    if constant_demand > 0 then
        local row_num = rows.map[structures.pack_item(electric_power)]
        if row_num ~= nil then
            ---@diagnostic disable: need-check-nil
            matrix[row_num][#columns.values+1] = matrix[row_num][#columns.values+1] + constant_demand
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

---@class SolverAggregateWithFuel : SolverAggregate
---@field fuel SolverItem
---@field fuel_amount number

---@param line_data LineData
---@param floor_id ObjectID
---@param machine_amount number
---@param factory_metadata FactoryMetadata?
---@param free_variables table<string, true>?
---@return SolverAggregateWithFuel
function matrix_engine.get_line_aggregate(line_data, floor_id, machine_amount, factory_metadata, free_variables)
    local line_aggregate = structures.aggregate.init(floor_id)  ---@type SolverAggregateWithFuel
    line_aggregate.machine_amount = machine_amount
    -- the index in the factory_data.top_floor.lines table can be different from the line_id!
    local total_effects = line_data.total_effects
    local machine_proto = line_data.machine_proto
    local speed_multiplier = 1 + (total_effects.speed / MAGIC_NUMBERS.effect_precision)
    local energy = line_data.recipe_energy
    -- hacky workaround for recipes with zero energy - this really messes up the matrix
    energy = math.max(energy, MAGIC_NUMBERS.minimum_energy)
    local time_per_craft = energy / (line_data.machine_speed * speed_multiplier)
    local total_crafts = machine_amount * (1 / time_per_craft)
    line_aggregate.production_ratio = total_crafts

    ---@param product SolverItem | FormattedProduct
    ---@param amount number?
    local function add_product(product, amount)
        local item_key = structures.pack_item(product)
        if factory_metadata and factory_metadata.byproducts[item_key] or free_variables and free_variables["item_"..item_key] then
           structures.map.add(line_aggregate.byproducts, product, amount)
        else
            structures.map.add(line_aggregate.products, product, amount)
        end
    end

    for _, product in pairs(line_data.products) do
        local prodded_amount = solver.util.determine_prodded_amount(product, total_effects)
        add_product(product, prodded_amount * total_crafts)
    end

    for _, ingredient in pairs(line_data.ingredients) do
        local ingredient_amount = (ingredient.amount * total_crafts)
        if ingredient.type ~= "fluid" then  -- doesn't apply to mining fluids
            ingredient_amount = ingredient_amount * line_data.resource_drain_rate
        end
        structures.map.add(line_aggregate.ingredients, ingredient, ingredient_amount)
    end

    -- Determine power (including potential fuel needs) and emissions
    local fuel_proto = line_data.fuel_proto
    local power, emissions = 0.0, 0.0
    local fuel, fuel_amount = nil, nil
    if energy > MAGIC_NUMBERS.minimum_energy then
        power, emissions = solver.util.determine_power_and_emissions(line_data, machine_amount, total_crafts)

        if machine_proto.energy_type == "burner" then  ---@cast fuel_proto -nil
            local burner = machine_proto.burner  ---@as MachineBurner
            fuel_amount = solver.util.determine_fuel_amount(line_data, power, machine_amount)

            fuel = {type=fuel_proto.type, name=line_data.fuel_name, amount=fuel_amount}  ---@type SolverItem
            structures.map.add(line_aggregate.ingredients, fuel)

            if fuel_proto.burnt_result then
                add_product({
                    type = "item",
                    name = fuel_proto.burnt_result,
                    amount = fuel_amount
                }--[[@as SolverItem]])
            end

            if burner.produces_spent_fluid then
                local spent_fluid = burner.spent_fluid or fuel_proto.spent_fluid
                if spent_fluid then
                    add_product({
                        type="fluid",
                        name=lib.temperature.name_with(spent_fluid.name, spent_fluid.temperature),
                        amount=fuel_amount * spent_fluid.amount
                    })
                end
            end

            power = 0  -- set power to 0 when fuel is used

        elseif machine_proto.energy_type == "heat" then
            local heat_item = {type="entity", name="custom-heat-power", amount=power}
            structures.map.add(line_aggregate.ingredients, heat_item)

            power = 0  -- set power to 0 when heat is used

        elseif machine_proto.energy_type == "void" then
            power = 0  -- set power to 0 while still polluting
        end
    end

    power = power + (line_data.beacon_power or 0)

    if power > 0 then
        local electric_item = {type="entity", name="custom-electric-power", amount=power}
        structures.map.add(line_aggregate.ingredients, electric_item)
    end

    if line_data.entities_require_heating and machine_proto.heating_energy > 0 then
        local heating_energy = machine_proto.heating_energy * machine_amount
        local heating_item = {type="entity", name="custom-heating-power", amount=heating_energy}
        structures.map.add(line_aggregate.ingredients, heating_item)
    end

    if emissions ~= 0 then  -- emissions are either produced or consumed
        local emission_name = "custom-" .. line_data.pollutant_type
        local emission_item = {type="entity", name=emission_name, amount=math.abs(emissions)}

        if emissions > 0 then
            add_product(emission_item)
        elseif emissions < 0 then
            structures.map.add(line_aggregate.ingredients, emission_item)
        end
    end

    -- needed for interface.set_line_result
    line_aggregate.fuel = fuel
    line_aggregate.fuel_amount = fuel_amount

    return line_aggregate
end

function matrix_engine.print_matrix(m)
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

---@class MappingStruct
---@field values string[]
---@field map table<string, integer>

---@param input_set table<string, true>
---@return MappingStruct
function matrix_engine.get_mapping_struct(input_set)
    -- turns a set into a mapping struct (eg matrix rows or columns)
    -- a "mapping struct" consists of a table with:
        -- key "values" - array of set values in sort order
        -- key "map" - map from input_set values to integers, where the integer is the position in "values"
    local values = matrix_engine.set_to_ordered_list(input_set)
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

---@generic T
---@param s table<T, true>
---@return T[]
function matrix_engine.set_to_ordered_list(s)
    local result = {}
    for k, _ in pairs(s) do table.insert(result, k) end
    table.sort(result)
    return result
end

-- Contains the raw matrix solver. Converts an NxN+1 matrix to reduced row-echelon form.
-- Based on the algorithm from octave: https://fossies.org/dox/FreeMat-4.2-Source/rref_8m_source.html
---@param m number[][]
function matrix_engine.to_reduced_row_echelon_form(m)
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
function matrix_engine.find_linearly_dependent_cols(matrix, ignore_last)
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

-- utility function that removes from a sorted array in place
---@generic T
---@param orig_table T[]
---@param value T
function matrix_engine.remove(orig_table, value)
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
---@generic T
---@param orig_table T[]
---@param value T
function matrix_engine.insert(orig_table, value)
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

return matrix_engine

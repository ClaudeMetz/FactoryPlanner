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
If there are more recipes than items, the problem is under-constrained and some recipes must be deleted. SpaceCatNote: Simplex algo i am working on might be able to do that automatically based on "costs" specified by the user
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
    Note that currently the factory planner doesn't do anything if a user clicks on byproducts, so at this time it is impossible to make voids.

Simplex Algo:
Author: SpaceCat~Chan ????-??-??
github: SpaceCat-Chan

based on https://www.hec.ca/en/cams/help/topics/The_steps_of_the_simplex_algorithm.pdf
--]]

matrix_solver = {}

function matrix_solver.transpose(m)
    local transposed = {}

    if #m == 0 then
        return transposed
    end

    for i = 1, #m[1] do
        local row = {}
        for j = 1, #m do
            table.insert(row, m[j][i])
        end
        table.insert(transposed, row)
    end
    return transposed
end

---@param matrix number[][]
---@return number[][]
local function just_copy(matrix)
    local copy = {}
    for k, v in pairs(matrix) do
        copy[k] = {}
        for kk, vv in pairs(v) do
            copy[k][kk] = vv
        end
    end
    return copy
end

function matrix_solver.derecurse_recipes(line, line_list, line_id_to_pos)
    for _, line in ipairs(line.lines) do
        if line.subfloor then
            local new_line_id_to_pos = {}
            matrix_solver.derecurse_recipes(line.subfloor, line_list, new_line_id_to_pos)
            line_id_to_pos[line.id] = new_line_id_to_pos
        else
            table.insert(line_list, line)
            line_id_to_pos[line.id] = #line_list
        end
    end
end

function matrix_solver.place_items_in_matrix(lines, required_items)
    local items = {}
    local inverse_map = {}
    local position = 1
    local function add_item(item)
        local index = item.type .. "_" .. item.name
        if items[index] == nil then
            items[index] = position
            inverse_map[position] = { type = item.type, name = item.name }
            position = position + 1
        end
    end

    for _, item in pairs(required_items) do
        add_item(item.proto)
    end

    for _, line in pairs(lines) do
        for _, item in pairs(line.recipe_proto.ingredients) do
            add_item(item)
        end
        for _, item in pairs(line.recipe_proto.products) do
            add_item(item)
        end
        if line.fuel_proto then
            add_item(line.fuel_proto)
        end
    end
    return items, position - 1, inverse_map
end

function matrix_solver.make_matrix(lines, items, item_count)
    local matrix = {}

    local function add_item(item, recipe, amount)
        local index = items[item.type .. "_" .. item.name]
        recipe[index] = recipe[index] + amount
    end

    for _, line in pairs(lines) do
        local recipe = {}
        local crafts_per_tick = calculation.util.determine_crafts_per_tick(line.machine_proto, line.recipe_proto, line.total_effects)
        for _ = 1, item_count do
            table.insert(recipe, 0)
        end
        for _, item in pairs(line.recipe_proto.ingredients) do
            add_item(item, recipe, -item.amount * crafts_per_tick * line.timescale)
        end
        for _, item in pairs(line.recipe_proto.products) do
            local prodded_amount = calculation.util.determine_prodded_amount(item, crafts_per_tick, line.total_effects)
            add_item(item, recipe, prodded_amount * crafts_per_tick * line.timescale)
        end
        if line.fuel_proto then
            local energy_consumption = calculation.util.determine_energy_consumption(line.machine_proto, 1, line.total_effects)
            local fuel_amount = calculation.util.determine_fuel_amount(energy_consumption, line.machine_proto.burner, line.fuel_proto.fuel_value, line.timescale)
            add_item(line.fuel_proto, recipe, -fuel_amount)
        end
        table.insert(matrix, recipe)
    end
    return matrix
end

local function calc_default_cost(item)
    if item and item.type == "fluid" then
        if item.name == "water" then
            return DEFAULT_SOLVER_COSTS.water
        else
            return DEFAULT_SOLVER_COSTS.fluid
        end
    else
        return DEFAULT_SOLVER_COSTS.item
    end
end

function matrix_solver.add_pseudo_recipes_and_calculate_costs(matrix, item_count, inverse_item_map, item_costs)
    local items_with_producers = {}
    local recipe_costs = {}
    for recipe_pos, recipe in pairs(matrix) do
        for item_pos, item in pairs(recipe) do
            if item > 0 then
                items_with_producers[item_pos] = items_with_producers[item_pos] or true
            end
        end
        recipe_costs[recipe_pos] = 0 -- 0 cost for basic recipes
    end
    local is_pseudo_recipe = {}
    for item_pos = 1, item_count do
        if not items_with_producers[item_pos] then
            is_pseudo_recipe[#matrix + 1] = true
            local pseudo_recipe = {}
            for pos = 1, item_count do
                if pos == item_pos then
                    table.insert(pseudo_recipe, 1)
                else
                    table.insert(pseudo_recipe, 0)
                end
            end
            local item_info = inverse_item_map[item_pos]
            local cost = item_costs[item_info.type][item_info.name]
            if cost and cost.cost then
                    recipe_costs[#matrix + 1] = cost.cost
            else
                recipe_costs[#matrix + 1] = calc_default_cost(item_info)
            end


            table.insert(matrix, pseudo_recipe)
        end
    end
    return recipe_costs, is_pseudo_recipe
end

function matrix_solver.add_item_requirements(matrix, items, item_count, subfactory_data)
    local requirements = {}
    for _ = 1, item_count do
        table.insert(requirements, 0)
    end
    for _, item in pairs(subfactory_data.top_level_products) do
        local index = items[item.proto.type .. "_" .. item.proto.name]
        if index then
            requirements[index] = item.amount
        end
    end
    table.insert(matrix, requirements)
end

local function add_custom_constraints(matrix, inverse_item_map, recipe_costs, cost_table)
    for position, item in pairs(inverse_item_map) do
        local cost_data = cost_table[item.type][item.name]
        if cost_data then
            --llog(item, cost_data)
            local allowed_as_byproduct = cost_data.allow_byproduct
            if allowed_as_byproduct == nil then
                allowed_as_byproduct = true
            end
            local allowed_as_ingredient = cost_data.allow_ingredient
            if allowed_as_ingredient == nil then
                allowed_as_ingredient = false
            end
            if allowed_as_ingredient then
                local new_row = {}
                for col=1,#matrix[1] do
                    if col == position then
                        table.insert(new_row, 1)
                    else
                        table.insert(new_row, 0)
                    end
                end
                table.insert(matrix, #matrix, new_row) -- insert before the constraints
                local cost = cost_data.cost or calc_default_cost(item)
                table.insert(recipe_costs, cost)
            end
            if not allowed_as_byproduct then
                for row=1,#matrix do
                    table.insert(matrix[row], matrix[row][position] * -1)
                end
            end
        end
    end
end

local function sum_item_results(matrix, solve_results, required_output, items)
    local per_line_item_results, global_item_results = {}, {}
    local function get_global(index)
        local global = global_item_results[index]
        if global == nil then
            global = { product = 0, byproduct = 0, ingredient = 0 }
            global_item_results[index] = global
        end
        return global
    end

    local function get_line(recipe, item)
        local line = per_line_item_results[recipe]
        if line == nil then
            line = {}
            per_line_item_results[recipe] = line
        end
        local item_res = line[item]
        if item_res == nil then
            item_res = { product = 0, byproduct = 0, ingredient = 0 }
            line[item] = item_res
        end
        return item_res
    end

    for _, item in pairs(required_output) do
        local index = items[item.proto.type .. "_" .. item.proto.name]
        global_item_results[index] = { product = 0, byproduct = 0, ingredient = item.amount }
    end
    for recipe_pos, recipe in pairs(matrix) do
        local recipe_speed = solve_results[recipe_pos]
        for item_pos, item in pairs(recipe) do
            local total_amount = item * recipe_speed
            if total_amount < 0 then
                local global = get_global(item_pos)
                local per_line = get_line(recipe_pos, item_pos)
                global.ingredient = global.ingredient - total_amount -- total amount is negative, so this is really "+ abs()"
                per_line.ingredient = -total_amount
            end
        end
    end

    for recipe_pos, recipe in pairs(matrix) do
        local recipe_speed = solve_results[recipe_pos]
        for item_pos, item in pairs(recipe) do
            local total_amount = item * recipe_speed
            if total_amount > 0 then
                local global = get_global(item_pos)
                local per_line = get_line(recipe_pos, item_pos)
                if per_line.ingredient > 0 then
                    global.ingredient = global.ingredient - per_line.ingredient
                    total_amount = total_amount - per_line.ingredient
                    per_line.ingredient = 0
                end
                local overproduction = total_amount - global.ingredient
                if overproduction > 0 then
                    total_amount = global.ingredient
                    global.ingredient = 0
                    per_line.byproduct = overproduction
                    global.byproduct = global.byproduct + overproduction
                end
                per_line.product = total_amount
            end
        end
    end
    return per_line_item_results, global_item_results
end

local function sums_to_class(list, reverse_map)
    local product = structures.class.init()
    local byproduct = structures.class.init()
    local ingredient = structures.class.init()
    for position, values in pairs(list) do
        if reverse_map[position] then -- no entry means that it's probably a dupe created by extra restricted byproducts
            structures.class.add(product, reverse_map[position], values.product)
            structures.class.add(byproduct, reverse_map[position], values.byproduct)
            structures.class.add(ingredient, reverse_map[position], values.ingredient)
        end
    end
    return product, byproduct, ingredient
end

function matrix_solver.run_matrix_solver(subfactory_data, check_linear_dependence)
    local products = subfactory_data.top_level_products
    local lines = {}
    -- line magic map tells us how to get from a position in the subfactory
    -- (with all it's nested subfloors) to a row in the matrix
    local line_magic_map = {}
    matrix_solver.derecurse_recipes(subfactory_data.top_floor, lines, line_magic_map)

    -- maps from 'type.."_"..name' to index in matrix
    local items, item_count, inverse_item_map = matrix_solver.place_items_in_matrix(lines, subfactory_data.top_level_products)

    --llog(lines, line_magic_map, items, item_count)

    --llog(subfactory_data.solver_costs)

    local matrix = matrix_solver.make_matrix(lines, items, item_count)
    -- if there is no water, items["fluid_water"] will just be nil, which is fine
    local recipe_costs, is_pseudo_recipe = matrix_solver.add_pseudo_recipes_and_calculate_costs(matrix, item_count, inverse_item_map, subfactory_data.solver_costs)
    matrix_solver.add_item_requirements(matrix, items, item_count, subfactory_data)
    add_custom_constraints(matrix, inverse_item_map, recipe_costs, subfactory_data.solver_costs)

    --matrix_solver.print_matrix(matrix)

    local results = matrix_solver.do_simplex_algo(matrix, item_count, recipe_costs, is_pseudo_recipe)

    -- we know how much each recipe is being run, now we just need to propegate that up the subfloor
    -- and also deal with product/byproduct stuffs

    matrix[#matrix] = nil -- remove row containing requirements

    local per_line_item_results, global_item_results = sum_item_results(matrix, results, subfactory_data.top_level_products, items)

    local function set_line_results(floor, magic_map)
        local total_machine_count = 0
        local total_electric_consumption = 0
        local total_pollution = 0
        local total_item_sums = {}

        local function add_sum_to_total(sum)
            for item_pos, item in pairs(sum) do
                if total_item_sums[item_pos] == nil then
                    total_item_sums[item_pos] = item
                else
                    local item_total = total_item_sums[item_pos]
                    item_total.product = item_total.product + item.product
                    item_total.byproduct = item_total.byproduct + item.byproduct
                    item_total.ingredient = item_total.ingredient + item.ingredient
                    if item_total.product ~= 0 and item_total.ingredient ~= 0 then
                        local difference = item_total.ingredient - item_total.product
                        item_total.ingredient = math.max(difference, 0)
                        item_total.product = math.max(-difference, 0)
                        --[[  equivalent to
                        local i, o = item_total.ingredient, item_total.product
                        if i > o then
                            item_total.ingredient = i - o
                            item_total.product = 0
                        else
                            item_total.product = o - i
                            item_total.ingredient = 0
                        end
                        ]]
                    end
                end
            end
        end

        for _, line in pairs(floor.lines) do
            if line.subfloor then
                local subfloor_results = set_line_results(line.subfloor, magic_map[line.id])

                total_machine_count = total_machine_count + math.ceil(subfloor_results.machine_count)
                total_electric_consumption = total_electric_consumption + subfloor_results.electric_energy_consumption
                total_pollution = total_pollution + subfloor_results.pollution
                add_sum_to_total(subfloor_results.sums)

                local product, byproduct, ingredient = sums_to_class(subfloor_results.sums, inverse_item_map)

                calculation.interface.set_line_result {
                    player_index = subfactory_data.player_index,
                    floor_id = floor.id,
                    line_id = line.id,
                    machine_count = subfloor_results.machine_count,
                    energy_consumption = subfloor_results.electric_energy_consumption,
                    pollution = subfloor_results.pollution,
                    Product = product,
                    Byproduct = byproduct,
                    Ingredient = ingredient,
                }
            else
                local index = magic_map[line.id]
                local machine_count = results[index]

                total_machine_count = total_machine_count + math.ceil(machine_count)

                local energy_consumption = calculation.util.determine_energy_consumption(line.machine_proto, machine_count, line.total_effects)
                local pollution = calculation.util.determine_pollution(line.machine_proto, line.recipe_proto, line.fuel_proto, line.total_effects, energy_consumption)
                local fuel_usage = nil
                if line.fuel_proto then
                    fuel_usage = calculation.util.determine_fuel_amount(energy_consumption, line.machine_proto.burner, line.fuel_proto.fuel_value, line.timescale)
                    energy_consumption = 0
                end
                total_electric_consumption = total_electric_consumption + energy_consumption
                total_pollution = total_pollution + pollution

                local crafts_per_tick = calculation.util.determine_crafts_per_tick(line.machine_proto, line.recipe_proto, line.total_effects)
                local production_ratio = calculation.util.determine_production_ratio(crafts_per_tick, machine_count, line.timescale, line.machine_proto.launch_sequence_time)

                local line_sums = per_line_item_results[index] or {}
                local product, byproduct, ingredient = sums_to_class(line_sums, inverse_item_map)

                add_sum_to_total(line_sums)

                calculation.interface.set_line_result {
                    player_index = subfactory_data.player_index,
                    floor_id = floor.id,
                    line_id = line.id,
                    machine_count = machine_count,
                    energy_consumption = energy_consumption,
                    pollution = pollution,
                    fuel_usage = fuel_usage,
                    production_ratio = production_ratio,
                    uncapped_production_ratio = production_ratio,
                    Product = product,
                    Byproduct = byproduct,
                    Ingredient = ingredient,
                }
            end
        end
        return {
            machine_count = total_machine_count,
            electric_energy_consumption = total_electric_consumption,
            pollution = total_pollution,
            sums = total_item_sums
        }
    end

    local top_floor_results = set_line_results(subfactory_data.top_floor, line_magic_map)

    local product, byproduct, ingredient = sums_to_class(top_floor_results.sums, inverse_item_map)

    -- copied from structures.class.add, and changed, because i need to do something non-standard
    for _, item in pairs(subfactory_data.top_level_products) do
        local type = item.proto.type
        local name = item.proto.name
        local amount_to_add = item.amount

        local type_table = product[type]
        type_table[name] = amount_to_add - (type_table[name] or 0)
        if type_table[name] == 0 then type_table[name] = nil end
    end

    calculation.interface.set_subfactory_result {
        player_index = subfactory_data.player_index,
        energy_consumption = top_floor_results.electric_energy_consumption,
        pollution = top_floor_results.pollution,
        Product = product,
        Byproduct = byproduct,
        Ingredient = ingredient,
        matrix_free_items = {}
    }
end

function matrix_solver.print_matrix(m)
    local s = ""
    s = s .. "{\n"
    for _, row in ipairs(m) do
        s = s .. "  {"
        for j, col in ipairs(row) do
            s = s .. tostring(col)
            if j < #row then
                local longest_in_row = 0
                for _, row2 in ipairs(m) do
                    if (string.len(tostring(row2[j])) > longest_in_row) then
                        longest_in_row = string.len(tostring(row2[j]))
                    end
                end
                s = s .. string.rep(" ", longest_in_row - string.len(tostring(col)) + 1)
            end
        end
        s = s .. "}\n"
    end
    s = s .. "}"
    llog(s)
end

--Simplex Algo starts here

---@param matrix number[][]
---@return number[][]


function matrix_solver.find_result_from_row(recipe_matrix, result, row, col_set, skip_count)
    local accumulated = 0
    for i = 1 + skip_count, #recipe_matrix[row] - 1 do
        accumulated = accumulated + recipe_matrix[row][i]
            * result[i]
    end
    return -accumulated
end

local function add_slacks(matrix, item_count, recipe_costs, is_pseudo_recipe)
    for recipe_pos, recipe in pairs(matrix) do
        for pos = 1, #matrix-1 do
            if pos == recipe_pos then
                table.insert(recipe, 1)
            else
                table.insert(recipe, 0)
            end
        end
        table.insert(recipe, recipe_costs[recipe_pos] or 0)
    end
end

local function get_pivot(matrix)
    local final_row = nil
    local final_col = nil
    local max_z = 0
    local last_row = matrix[#matrix]
    for col, z in pairs(last_row) do
        local min_ratio_value = nil
        if z > max_z then
            for row, current_row in pairs(matrix) do
                local x = current_row[col]
                if row < #matrix and x > 0 then
                    local c = current_row[#current_row]
                    local ratio = c / x
                    if min_ratio_value == nil or ratio < min_ratio_value then
                        min_ratio_value = ratio
                        final_row = row
                    end
                end
            end
        end
        if min_ratio_value ~= nil then
            final_col = col
            max_z = z
        end
    end
    return max_z ~= 0, final_col, final_row
end

local abs = math.abs
local function do_pivot(mat, pivot_row, pivot_col)
    -- for [row, !column], divide by [row, column]
    -- for [row, column], set = 1
    -- for [!row, !column], subtract by [!row, column] * [row, !column]
    -- for [!row, column], set = 0
    -- skip rows where [!row, col] is 0
    -- skip columns where [row, !column] is 0
    local row_count = #mat
    local column_count = #mat[1]
    local pivot_row_contents = mat[pivot_row]
    local pivot = pivot_row_contents[pivot_col]

    local cols_to_do = {}
    for col = 1, column_count do
        if col ~= pivot_col and pivot_row_contents[col] ~= 0 then
            table.insert(cols_to_do, col)
        end
    end

    for _, col in pairs(cols_to_do) do
        local value = pivot_row_contents[col] / pivot
        if abs(value) < 1e-8 then
            value = 0
        end
        pivot_row_contents[col] = value
    end

    pivot_row_contents[pivot_col] = 1


    for row = 1, row_count do
        if row ~= pivot_row and mat[row][pivot_col] ~= 0 then
            local row_contents = mat[row]
            for _, col in pairs(cols_to_do) do
                local value = row_contents[col] - row_contents[pivot_col] * pivot_row_contents[col]
                if abs(value) < 1e-8 then
                    value = 0
                end
                row_contents[col] = value
            end
        end
    end

    for row = 1, row_count do
        if row ~= pivot_row then
            mat[row][pivot_col] = 0
        end
    end
end

local function finalize(mat, original)
    local result = {}
    local original_variable_count = #original[1]
    for row, _ in pairs(original) do
        if row < #mat then
            local col_of_extra_variable = original_variable_count + row
            result[row] = -mat[#mat][col_of_extra_variable]
        end
    end
    return result
end

function matrix_solver.do_simplex_algo(matrix, item_count, recipe_costs, is_pseudo_recipe)
    if #matrix == 0 then
        return
    end
    local copy = just_copy(matrix)
    local original = just_copy(copy)
    --llog("\n\n\n\n ============== 1 ==============")
    --matrix_solver.print_matrix(copy)
    add_slacks(copy, item_count, recipe_costs, is_pseudo_recipe)
    --llog("\n\n\n\n ============== 2 ==============")
    --matrix_solver.print_matrix(copy)
    local loop = true
    local counter = 1
    while loop do
        local c, col, row = get_pivot(copy)
        loop = c
        if c then
            do_pivot(copy, row, col)
            --llog("\n\n\n\n ============== post pivot "..tostring(counter).." ==============\npivot around: {row: "..tostring(row)..", col: "..tostring(col).."}\n")
            --matrix_solver.print_matrix(copy)
            counter = counter + 1
        end
    end
    --llog("\n\n\n\n ============== 3 ==============")
    --matrix_solver.print_matrix(copy)
    local results = finalize(copy, original)
    --llog("\n\n\n\n ============== 4 ==============")
    --matrix_solver.print_matrix(original)
    --local s = "R: {"
    --for _, i in pairs(results) do
    --    s = s .. tostring(i) .. " "
    --end
    --llog(s .. "}")
    return results
end

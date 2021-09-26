local M = {}
local Problem = require("data.calculation.Problem")
local Matrix = require("data.calculation.Matrix")
local SparseMatrix = require("data.calculation.SparseMatrix")

local insufficient_penalty = 2 ^ 20
local redundant_penalty = 2 ^ 10
local products_priority_penalty = 2 ^ 0
local ingredients_priority_penalty = 2 ^ 5
local machine_count_penalty = 2 ^ 0

function M.create_problem(subfactory_name, flat_recipe_lines, normalized_references)
    local problem = Problem(subfactory_name)

    local function add_item_factor(constraint_map, name, factor)
        constraint_map["balance|" .. name] = factor
        if factor > 0 then
            constraint_map["product_reference|" .. name] = factor
        elseif factor < 0 then
            constraint_map["ingredient_reference|" .. name] = -factor
        end
    end

    for id, v in pairs(flat_recipe_lines) do
        problem:add_objective(id, machine_count_penalty, true)
        local constraint_map = {}

        if v.maximum_machine_count then
            local key = "maximum|" .. id
            problem:add_le_constraint(key, v.maximum_machine_count)
            constraint_map[key] = 1
        end
        if v.minimum_machine_count then
            local key = "minimum|" .. id
            problem:add_ge_constraint(key, v.minimum_machine_count)
            constraint_map[key] = 1
        end

        for name, u in pairs(v.products) do
            local amount = u.amount_per_machine_by_second
            add_item_factor(constraint_map, name, amount)

            if #u.neighbor_recipe_lines >= 2 then
                local balance_key = string.format("products_priority_balance|%s:%s", id, name)
                problem:add_eq_constraint(balance_key, 0)
                constraint_map[balance_key] = amount
                for priority, neighbor in ipairs(u.neighbor_recipe_lines) do
                    local transfer_key = string.format("transfer|%s=>%s:%s", id, neighbor.normalized_id, name)
                    local penalty = (priority - 1) * products_priority_penalty
                    if problem:is_exist_objective(transfer_key) then
                        problem:add_objective_penalty(transfer_key, penalty)
                    else
                        problem:add_objective(transfer_key, penalty)
                    end
                    problem:add_subject_term(transfer_key, {
                        [balance_key] = -1
                    })
                end
                local implicit_key = string.format("implicit_transfer|%s=>(?):%s", id, name)
                local penalty = #u.neighbor_recipe_lines * products_priority_penalty
                problem:add_objective(implicit_key, penalty)
                problem:add_subject_term(implicit_key, {
                    [balance_key] = -1
                })
            end 
        end

        for name, u in pairs(v.ingredients) do
            local amount = u.amount_per_machine_by_second
            add_item_factor(constraint_map, name, -amount)

            if #u.neighbor_recipe_lines >= 2 then
                local balance_key = string.format("ingredients_priority_balance|%s:%s", id, name)
                problem:add_eq_constraint(balance_key, 0)
                constraint_map[balance_key] = -amount
                for priority, neighbor in ipairs(u.neighbor_recipe_lines) do
                    local transfer_key = string.format("transfer|%s=>%s:%s", neighbor.normalized_id, id, name)
                    local penalty = (priority - 1) * ingredients_priority_penalty
                    if problem:is_exist_objective(transfer_key) then
                        problem:add_objective_penalty(transfer_key, penalty)
                    else
                        problem:add_objective(transfer_key, penalty)
                    end
                    problem:add_subject_term(transfer_key, {
                        [balance_key] = 1
                    })
                end
                local implicit_key = string.format("implicit_transfer|(?)=>%s:%s", id, name)
                local penalty = #u.neighbor_recipe_lines * ingredients_priority_penalty
                problem:add_objective(implicit_key, penalty)
                problem:add_subject_term(implicit_key, {
                    [balance_key] = 1
                })
            end 
        end

        problem:add_subject_term(id, constraint_map)
    end
    
    local items = M.get_include_items(flat_recipe_lines, normalized_references)
    for name, v in pairs(items) do
        if v.product and v.ingredient then
            problem:add_eq_constraint("balance|" .. name, 0)
        end
        if v.product then
            local key = "implicit_ingredient|" .. name
            local penalty = redundant_penalty
            if v.ingredient  then
                problem:add_objective(key, penalty)
            end

            local constraint_map = {}
            add_item_factor(constraint_map, name, -1)
            problem:add_subject_term(key, constraint_map)
        end
        if v.ingredient then
            local key = "implicit_product|" .. name
            local penalty = insufficient_penalty
            if v.product then
                problem:add_objective(key, penalty)
            end

            local constraint_map = {}
            add_item_factor(constraint_map, name, 1)
            problem:add_subject_term(key, constraint_map)
        end
        if v.reference then
            local r = normalized_references[name]
            if v.product then
                problem:add_ge_constraint("product_reference|" .. name, r.amount_per_second)
            end
            if v.ingredient then
                problem:add_ge_constraint("ingredient_reference|" .. name, r.amount_per_second)
            end
        end
    end

    return problem
end

function M.get_include_items(flat_recipe_lines, normalized_references)
    local set = {}
    local function add_set(key, type)
        if not set[key] then
            set[key] = {
                name = key,
                product = false,
                ingredient = false,
                reference = false,
            }
        end
        set[key][type] = true
    end

    for _, l in pairs(flat_recipe_lines) do
        for k, _ in pairs(l.products) do
            add_set(k, "product")
        end
        for k, _ in pairs(l.ingredients) do
            add_set(k, "ingredient")
        end
    end
    for k, _ in pairs(normalized_references) do
        add_set(k, "reference")
    end

    return set
end

local had, had_pow, diag = Matrix.hadamard_product, Matrix.hadamard_power, SparseMatrix.diag
local tolerance = MARGIN_OF_ERROR
local iterate_limit = 200

function M.primal_dual_interior_point(problem)
    local debug_print = log

    local A = problem:make_subject_sparse_matrix()
    local AT = A:T()
    local b = problem:make_dual_factors()
    local c = problem:make_primal_factors()
    local p_degree = problem.primal_length
    local d_degree = problem.dual_length
    local x = Matrix.new_vector(p_degree):fill(1)
    local y = Matrix.new_vector(d_degree):fill(0)
    local s = c:clone()

    for y = 1, p_degree do
        s[y][1] = math.max(1, s[y][1])
    end

    local function fvg(...)
        local currents = Matrix.join_vector{...}
        return function(target, factors, indexes)
            debug_print(string.format("generate flee values: target = %f", target))
            local tf = 0
            for _, v in ipairs(factors) do
                tf = tf + math.abs(v)
            end
            local ret = {}
            local sol = target / tf
            for i, k in ipairs(indexes) do
                ret[i] = sol * factors[i] / math.abs(factors[i])
                debug_print(string.format(
                    "index = %i, factor = %f, current = %f, solution = %f",
                    k, factors[i], currents[k][1], sol
                ))
            end
            return ret
        end
    end

    debug_print(string.format("-- solve %s --", problem.name))
    for i = 0, iterate_limit do
        local dual = AT * y + s - c
        local primal = A * x - b
        local duality_gap = had(x, s)

        local d_sat = dual:euclidean_norm() / d_degree
        local p_sat = primal:euclidean_norm() / p_degree
        local dg_sat = duality_gap:euclidean_norm() / p_degree

        debug_print(string.format(
            "i = %i, primal = %f, dual = %f, duality_gap = %f", 
            i, p_sat, d_sat, dg_sat
        ))
        if math.max(d_sat, p_sat, dg_sat) <= tolerance then
            break
        end

        local s_inv = had_pow(s, -1)

        local u = M.sigmoid((d_sat + p_sat) * dg_sat, -1)
        local ue = Matrix.new_vector(p_degree):fill(u)
        local dg_aug = had(s_inv, duality_gap - ue)

        local D = diag(had(s_inv, x))
        local N = A * D * AT

        local r_asd = A * (-D * dual + dg_aug) - primal
        local y_asd = M.gaussian_elimination(N:insert_column(r_asd), fvg(y))
        local s_asd = AT * -y_asd - dual
        local x_asd = -D * s_asd - dg_aug

        -- local cor = had(x, s) + had(x, s_asd) + had(x_asd, s) + had(x_asd, s_asd)
        -- local r_agg = Matrix.join_vector{
        --     dual,
        --     primal,
        --     duality_gap + cor - cen,
        -- }
        -- local agg = M.gaussian_elimination(D:clone():insert_column(-r_agg), fvg(x, y, s))
        -- local x_agg, y_agg, s_agg = split(agg)

        local p_step = M.get_max_step(x, x_asd)
        local d_step = M.get_max_step(s, s_asd)
        debug_print(string.format(
            "p_step = %f, d_step = %f, barrier = %f",
            p_step, d_step, u
        ))

        x = x + p_step * x_asd
        y = y + d_step * y_asd
        s = s + d_step * s_asd
    end
    debug_print("-- complete solve --")
    debug_print("variable x:\n" .. problem:dump_primal(x))
    -- debug_print("variable y:\n" .. problem:dump_dual(y))
    -- debug_print("variable s:\n" .. problem:dump_primal(s))

    return problem:convert_result(x)
end

function M.sigmoid(value, min, max)
    min = min or 0
    max = max or 1
    return (max - min) / (1 + math.exp(-value)) + min
end

function M.get_max_step(v, dir)
    local height = v.height
    local f = 1 - tolerance
    local ret = 1
    for y = 1, height do
        local a, b = v[y][1], dir[y][1]
        if b < 0 then
            ret = math.min(ret, f * a / -b)
        end
    end
    return ret
end

function M.gaussian_elimination(matrix, flee_value_generator)
    local height, width = matrix.height, matrix.width

    local function select_pivot(s, x)
        local max_value, max_index, raw_max_value = 0, nil, nil
        for y = s, height do
            local r = matrix:get(y, x)
            local a = math.abs(r)
            if max_value < a then
                max_value = a
                max_index = y
                raw_max_value = r
            end
        end
        return max_index, raw_max_value
    end

    local i = 1
    for x = 1, width do
        local pi, pv = select_pivot(i, x)
        if pi then
            matrix:row_swap(i, pi)
            for k = i + 1, height do
                local f = -matrix:get(k, x) / pv
                matrix:row_trans(k, i, f)
                matrix:set(k, x, 0)
            end
            i = i + 1
        end
    end

    local sol = {}
    for y = height, 1, -1 do
        local total, factors, indexes = 0, {}, {}
        for x, v in matrix:iterate_row(y) do
            if sol[x] then
                total = total - sol[x] * v
            elseif x == width then
                total = total + v
            else
                table.insert(factors, v)
                table.insert(indexes, x)
            end
        end

        local l = #indexes
        if l == 1 then
            sol[indexes[1]] = total / factors[1]
        elseif l >= 2 then
            local res = flee_value_generator(total, factors, indexes)
            for k, x in ipairs(indexes) do
                sol[x] = res[k]
            end
        end
    end
    return Matrix.list_to_vector(sol, width - 1)
end

return M
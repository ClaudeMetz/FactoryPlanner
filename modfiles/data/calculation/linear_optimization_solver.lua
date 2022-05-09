--- Create and solve linear programming problems (a.k.a linear optimization).
-- @module linear_optimization_solver
-- @license MIT
-- @author B_head

local M = {}
local Problem = require("data.calculation.Problem")
local Matrix = require("data.calculation.Matrix")
local SparseMatrix = require("data.calculation.SparseMatrix")

local machine_count_penalty = 2 ^ 0
local shortage_penalty = 2 ^ 25
local surplusage_penalty = 2 ^ 15
local products_priority_penalty = 2 ^ 5
local ingredients_priority_penalty = 2 ^ 10

local function get_include_items(flat_recipe_lines, normalized_references)
    local set = {}
    local function add_set(key, type)
        if not set[key] then
            set[key] = {
                id = key,
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

local function create_item_flow_graph(flat_recipe_lines)
    local ret = {}
    local function add(a, type, b, ratio)
        if not ret[a] then
            ret[a] = {
                from = {},
                to = {},
                visited = false,
                cycled = false,
            }
        end
        table.insert(ret[a][type], {id=b, ratio=ratio})
    end

    for _, l in pairs(flat_recipe_lines) do
        for _, a in pairs(l.products) do
            for _, b in pairs(l.ingredients) do
                local ratio = b.amount_per_machine_by_second / a.amount_per_machine_by_second
                add(a.normalized_id, "to", b.normalized_id, ratio)
            end
        end
        for _, a in pairs(l.ingredients) do
            for _, b in pairs(l.products) do
                local ratio = b.amount_per_machine_by_second / a.amount_per_machine_by_second
                add(a.normalized_id, "from", b.normalized_id, ratio)
            end
        end
    end
    return ret
end

local function detect_cycle_dilemma_impl(item_flow_graph, id, path)
    local current = item_flow_graph[id]
    if current.visited then
        local included = false
        for _, path_id in ipairs(path) do
            if path_id == id then
                included = true
            end
            if included then
                item_flow_graph[path_id].cycled = true
            end
        end
        return
    end

    current.visited = true
    table.insert(path, id)
    for _, n in ipairs(current.to) do
        detect_cycle_dilemma_impl(item_flow_graph, n.id, path)
    end
    table.remove(path)
end

local function detect_cycle_dilemma(flat_recipe_lines)
    local item_flow_graph = create_item_flow_graph(flat_recipe_lines)
    local path = {}
    for id, _ in pairs(item_flow_graph) do
        if not item_flow_graph[id].visited then
            detect_cycle_dilemma_impl(item_flow_graph, id, path)
        end
    end

    local ret = {}
    for id, v in pairs(item_flow_graph) do
        ret[id] = {product=v.cycled, ingredient=v.cycled}
    end
    return ret
end

--- Create linear programming problems.
-- @tparam string problem_name Problem name.
-- @param flat_recipe_lines List returned by @{solver_util.to_flat_recipe_lines}.
-- @param normalized_references List returned by @{solver_util.normalize_references}.
-- @treturn Problem Created problem object.
function M.create_problem(problem_name, flat_recipe_lines, normalized_references)
    local function add_item_factor(subject_map, name, factor)
        subject_map["balance|" .. name] = factor
        if factor > 0 then
            subject_map["product_reference|" .. name] = factor
        elseif factor < 0 then
            subject_map["ingredient_reference|" .. name] = -factor
        end
    end

    local problem = Problem(problem_name)
    local need_slack = detect_cycle_dilemma(flat_recipe_lines)
    for recipe_id, v in pairs(flat_recipe_lines) do
        problem:add_objective_term(recipe_id, machine_count_penalty, true)
        local subject_map = {}
        local is_maximum_limit = false

        if v.maximum_machine_count then
            local key = "maximum|" .. recipe_id
            problem:add_le_constraint(key, v.maximum_machine_count)
            subject_map[key] = 1
            is_maximum_limit = true
        end
        if v.minimum_machine_count then
            local key = "minimum|" .. recipe_id
            problem:add_ge_constraint(key, v.minimum_machine_count)
            subject_map[key] = 1
        end

        for item_id, u in pairs(v.products) do
            local amount = u.amount_per_machine_by_second
            add_item_factor(subject_map, item_id, amount)
            if is_maximum_limit then
                need_slack[item_id].product = true
            end

            if #u.neighbor_recipe_lines >= 2 then
                local balance_key = string.format("products_priority_balance|%s:%s", recipe_id, item_id)
                problem:add_eq_constraint(balance_key, 0)
                subject_map[balance_key] = amount
                for priority, neighbor in ipairs(u.neighbor_recipe_lines) do
                    local transfer_key = string.format("transfer|%s=>%s:%s", recipe_id, neighbor.normalized_id, item_id)
                    local penalty = (priority - 1) * products_priority_penalty
                    if problem:is_exist_objective(transfer_key) then
                        problem:add_objective_cost(transfer_key, penalty)
                    else
                        problem:add_objective_term(transfer_key, penalty)
                    end
                    problem:add_constraint_term(transfer_key, {
                        [balance_key] = -1
                    })
                end
                local implicit_key = string.format("implicit_transfer|%s=>(?):%s", recipe_id, item_id)
                local penalty = #u.neighbor_recipe_lines * products_priority_penalty
                problem:add_objective_term(implicit_key, penalty)
                problem:add_constraint_term(implicit_key, {
                    [balance_key] = -1
                })
            end 
        end

        for item_id, u in pairs(v.ingredients) do
            local amount = u.amount_per_machine_by_second
            add_item_factor(subject_map, item_id, -amount)
            if is_maximum_limit then
                need_slack[item_id].ingredient = true
            end

            if #u.neighbor_recipe_lines >= 2 then
                local balance_key = string.format("ingredients_priority_balance|%s:%s", recipe_id, item_id)
                problem:add_eq_constraint(balance_key, 0)
                subject_map[balance_key] = -amount
                for priority, neighbor in ipairs(u.neighbor_recipe_lines) do
                    local transfer_key = string.format("transfer|%s=>%s:%s", neighbor.normalized_id, recipe_id, item_id)
                    local penalty = (priority - 1) * ingredients_priority_penalty
                    if problem:is_exist_objective(transfer_key) then
                        problem:add_objective_cost(transfer_key, penalty)
                    else
                        problem:add_objective_term(transfer_key, penalty)
                    end
                    problem:add_constraint_term(transfer_key, {
                        [balance_key] = 1
                    })
                end
                local implicit_key = string.format("implicit_transfer|(?)=>%s:%s", recipe_id, item_id)
                local penalty = #u.neighbor_recipe_lines * ingredients_priority_penalty
                problem:add_objective_term(implicit_key, penalty)
                problem:add_constraint_term(implicit_key, {
                    [balance_key] = 1
                })
            end 
        end

        problem:add_constraint_term(recipe_id, subject_map)
    end
    
    local items = get_include_items(flat_recipe_lines, normalized_references)
    for item_id, v in pairs(items) do
        if v.product and v.ingredient then
            problem:add_eq_constraint("balance|" .. item_id, 0)
        end
        if v.ingredient and need_slack[item_id].ingredient then
            local key = "implicit_ingredient|" .. item_id
            local penalty = surplusage_penalty
            problem:add_objective_term(key, penalty)
            local subject_map = {}
            add_item_factor(subject_map, item_id, -1)
            problem:add_constraint_term(key, subject_map)
        end
        if v.product and need_slack[item_id].product then
            local key = "implicit_product|" .. item_id
            local penalty = shortage_penalty
            problem:add_objective_term(key, penalty)
            local subject_map = {}
            add_item_factor(subject_map, item_id, 1)
            problem:add_constraint_term(key, subject_map)
        end
        if v.reference then
            local r = normalized_references[item_id]
            if v.product then
                problem:add_ge_constraint("product_reference|" .. item_id, r.amount_per_second)
            end
            if v.ingredient then
                problem:add_ge_constraint("ingredient_reference|" .. item_id, r.amount_per_second)
            end
        end
    end

    return problem
end

local debug_print = log
local had, had_pow, diag = Matrix.hadamard_product, Matrix.hadamard_power, SparseMatrix.diag
local tolerance = MARGIN_OF_ERROR
local step_limit = 1 - (2 ^ -20)
local machine_epsilon = (2 ^ -52)
local tiny_number = math.sqrt(2 ^ -970)
local iterate_limit = 200

local function force_variables_constraint(variables)
    local height = variables.height
    for y = 1, height do
        variables[y][1] = math.max(tiny_number, variables[y][1])
    end
end

local function sigmoid(value, min, max)
    min = min or 0
    max = max or 1
    return (max - min) / (1 + math.exp(-value)) + min
end

local function get_max_step(v, dir)
    local height = v.height
    local ret = 1
    for y = 1, height do
        local a, b = v[y][1], dir[y][1]
        if b < 0 then
            ret = math.min(ret, step_limit * (a / -b))
        end
    end
    return ret
end

--- Solve linear programming problems.
-- @see http://www.cas.mcmaster.ca/~cs777/presentations/NumericalIssue.pdf
-- @tparam Problem problem Problems to solve.
-- @tparam table prev_raw_solution The value returned by @{Problem:pack_pdip_variables}.
-- @treturn {[string]=number,...} Solution to problem.
-- @treturn table Packed table of raw solution.
function M.primal_dual_interior_point(problem, prev_raw_solution)
    local A = problem:make_subject_sparse_matrix()
    local AT = A:T()
    local b = problem:make_dual_coefficients()
    local c = problem:make_primal_coefficients()
    local p_degree = problem.primal_length
    local d_degree = problem.dual_length
    local x = problem:make_primal_find_variables(prev_raw_solution)
    local y = problem:make_dual_find_variables(prev_raw_solution)
    local s = problem:make_dual_slack_variables(prev_raw_solution)

    debug_print(string.format("-- solve %s --", problem.name))
    for i = 0, iterate_limit do
        force_variables_constraint(x)
        force_variables_constraint(s)

        local dual = AT * y + s - c
        local primal = A * x - b
        local duality_gap = had(x, s)

        local d_sat = (d_degree == 0) and 0 or dual:euclidean_norm() / d_degree
        local p_sat = (p_degree == 0) and 0 or primal:euclidean_norm() / p_degree
        local dg_sat = (p_degree == 0) and 0 or duality_gap:euclidean_norm() / p_degree

        debug_print(string.format(
            "i = %i, primal = %f, dual = %f, duality_gap = %f", 
            i, p_sat, d_sat, dg_sat
        ))
        if math.max(d_sat, p_sat, dg_sat) <= tolerance then
            break
        end

        local fvg = M.create_default_flee_value_generator(y)
        local s_inv = had_pow(s, -1)

        local u = sigmoid((d_sat + p_sat) * dg_sat, -1)
        local ue = Matrix.new_vector(p_degree):fill(u)
        local dg_aug = had(s_inv, duality_gap - ue)

        local ND = diag(had(s_inv, x))
        local N = A * ND * AT
        local L, FD, U = M.cholesky_factorization(N)
        L = L * FD

        local r_asd = A * (-ND * dual + dg_aug) - primal
        local y_asd = M.lu_solve_linear_equation(L, U, r_asd, fvg)
        local s_asd = AT * -y_asd - dual
        local x_asd = -ND * s_asd - dg_aug

        -- local cor = had(x, s) + had(x, s_asd) + had(x_asd, s) + had(x_asd, s_asd)
        -- local r_agg = Matrix.join_vector{
        --     dual,
        --     primal,
        --     duality_gap + cor - cen,
        -- }
        -- local agg = M.gaussian_elimination(D:clone():insert_column(-r_agg), fvg(x, y, s))
        -- local x_agg, y_agg, s_agg = split(agg)

        local p_step = get_max_step(x, x_asd)
        local d_step = get_max_step(s, s_asd)
        debug_print(string.format(
            "p_step = %f, d_step = %f, barrier = %f",
            p_step, d_step, u
        ))

        x = x + p_step * x_asd
        y = y + d_step * y_asd
        s = s + d_step * s_asd
    end
    debug_print(string.format("-- complete solve %s --", problem.name))
    debug_print("variables x:\n" .. problem:dump_primal(x))
    debug_print("factors c:\n" .. problem:dump_primal(c))
    -- debug_print("variables y:\n" .. problem:dump_dual(y))
    debug_print("factors b:\n" .. problem:dump_dual(b))
    -- debug_print("variables s:\n" .. problem:dump_primal(s))

    return problem:filter_solution_to_result(x), problem:pack_pdip_variables(x, y, s)
end

--- Reduce an augmented matrix into row echelon form.
-- @todo Refactoring for use in matrix solvers.
-- @tparam Matrix A Matrix equation.
-- @tparam Matrix b Column vector.
-- @treturn Matrix Matrix of row echelon form.
function M.gaussian_elimination(A, b)
    local height, width = A.height, A.width
    local ret_A = A:clone():insert_column(b)

    local function select_pivot(s, x)
        local max_value, max_index, raw_max_value = 0, nil, nil
        for y = s, height do
            local r = ret_A:get(y, x)
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
    for x = 1, width + 1 do
        local pi, pv = select_pivot(i, x)
        if pi then
            ret_A:row_swap(i, pi)
            for k = i + 1, height do
                local f = -ret_A:get(k, x) / pv
                ret_A:row_trans(k, i, f)
                ret_A:set(k, x, 0)
            end
            i = i + 1
        end
    end

    local ret_b = ret_A:remove_column()
    return ret_A, ret_b
end

--- LU decomposition of the symmetric matrix.
-- @tparam Matrix A Symmetric matrix.
-- @treturn Matrix Lower triangular matrix.
-- @treturn Matrix Diagonal matrix.
-- @treturn Matrix Upper triangular matrix.
function M.cholesky_factorization(A)
    assert(A.height == A.width)
    local size = A.height
    local L, D = SparseMatrix(size, size), SparseMatrix(size, size)
    for i = 1, size do
        local a_values = {}
        for x, v in A:iterate_row(i) do
            a_values[x] = v
        end

        for k = 1, i do
            local i_it, k_it = L:iterate_row(i), L:iterate_row(k)
            local i_r, i_v = i_it()
            local k_r, k_v = k_it()

            local sum = 0
            while i_r and k_r do
                if i_r < k_r then
                    i_r, i_v = i_it()
                elseif i_r > k_r then
                    k_r, k_v = k_it()
                else -- i_r == k_r
                    local d = D:get(i_r, k_r)
                    sum = sum + i_v * k_v * d
                    i_r, i_v = i_it()
                    k_r, k_v = k_it()
                end
            end

            local a = a_values[k] or 0
            local b = a - sum
            if i == k then
                D:set(k, k, math.max(b, a * machine_epsilon))
                L:set(i, k, 1)
            else
                local c = D:get(k, k)
                local v = b / c
                L:set(i, k, v)
            end
        end
    end
    return L, D, L:T()
end

local function substitution(s, e, m, A, b, flee_value_generator)
    local sol = {}
    for y = s, e, m do
        local total, factors, indexes = b:get(y, 1), {}, {}
        for x, v in A:iterate_row(y) do
            if sol[x] then
                total = total - sol[x] * v
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
    return Matrix.list_to_vector(sol, A.width)
end

--- Use LU-decomposed matrices to solve linear equations.
-- @tparam Matrix L Lower triangular matrix.
-- @tparam Matrix U Upper triangular matrix.
-- @tparam Matrix b Column vector.
-- @tparam function flee_value_generator Callback function that generates the value of free variable.
-- @treturn Matrix Solution of linear equations.
function M.lu_solve_linear_equation(L, U, b, flee_value_generator)
    local t = M.forward_substitution(L, b, flee_value_generator)
    return M.backward_substitution(U, t, flee_value_generator)
end

--- Use lower triangular matrix to solve linear equations.
-- @tparam Matrix L Lower triangular matrix.
-- @tparam Matrix b Column vector.
-- @tparam function flee_value_generator Callback function that generates the value of free variable.
-- @treturn Matrix Solution of linear equations.
function M.forward_substitution(L, b, flee_value_generator)
    return substitution(1, L.height, 1, L, b, flee_value_generator)
end

--- Use upper triangular matrix to solve linear equations.
-- @tparam Matrix U Upper triangular matrix.
-- @tparam Matrix b Column vector.
-- @tparam function flee_value_generator Callback function that generates the value of free variable.
-- @treturn Matrix Solution of linear equations.
function M.backward_substitution(U, b, flee_value_generator)
    return substitution(U.height, 1, -1, U, b, flee_value_generator)
end

--- Create to callback function that generates the value of free variable.
-- @tparam Matrix Vector to be referenced in debug output.
-- @treturn function Callback function.
function M.create_default_flee_value_generator(...)
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

return M
--- Helper for generating linear programming problems.
-- @classmod Problem
-- @alias P
-- @license MIT
-- @author B_head

local P, S = {}, {}
local C = require("data.calculation.class")
local Matrix = require("data.calculation.Matrix")
local SparseMatrix = require("data.calculation.SparseMatrix")

--- Constructor.
-- @tparam string name Name of the problem.
function P:__new(name)
    self.name = name
    self.primal = {}
    self.primal_length = 0
    self.dual = {}
    self.dual_length = 0
    self.subject_terms = {}
end

--- Add the variables to optimize and a term for the objective function.
-- @tparam string key Term key.
-- @tparam number cost Coefficient of the term.
-- @tparam bool is_result If ture, variables are included in the output of the solution.
function P:add_objective_term(key, cost, is_result)
    assert(not self.primal[key])
    self.primal_length = self.primal_length + 1
    self.primal[key] = {
        key = key,
        index = self.primal_length,
        value = cost or 1,
        is_result = is_result or false,
    }
end

--- Is there an objective term that corresponds to the key?
-- @tparam string key Term key.
-- @treturn bool True if exists.
function P:is_exist_objective(key)
    return self.primal[key] ~= nil
end

--- Add to the coefficients of the terms of the objective function.
-- @tparam string key Term key.
-- @tparam number cost Value to be added.
function P:add_objective_cost(key, cost)
    assert(self.primal[key])
    self.primal[key].value = self.primal[key].value + cost
end

--- Add equality constraints.
-- @tparam string key Constraint key.
-- @tparam number target The value that needs to match the result of the constraint expression.
function P:add_eq_constraint(key, target)
    assert(not self.dual[key])
    self.dual_length = self.dual_length + 1
    self.dual[key] = {
        key = key,
        index = self.dual_length,
        value = target or 0,
    }
end

--- Add inequality constraints of equal or less.
-- @tparam string key Constraint key.
-- @tparam number limit The upper bound on the result of the constraint equation.
function P:add_le_constraint(key, limit)
    local slack_key = "<slack>" .. key
    self:add_eq_constraint(key, limit)
    self:add_objective_term(slack_key, 0, false)
    self:add_constraint_term(slack_key, {
        [key] = 1,
    })
end

--- Add inequality constraints of equal or greater.
-- @tparam string key Constraint key.
-- @tparam number limit The lower bound on the result of the constraint equation.
function P:add_ge_constraint(key, limit)
    local slack_key = "<slack>" .. key
    self:add_eq_constraint(key, limit)
    self:add_objective_term(slack_key, 0, false)
    self:add_constraint_term(slack_key, {
        [key] = -1,
    })
end

--- Is there an constraint that corresponds to the key?
-- @tparam string key Constraint key.
-- @treturn bool True if exists.
function P:is_exist_constraint(key)
    return self.dual[key] ~= nil
end

--- Add a term for the constraint equation.
-- @tparam string objective_key Objective term key.
-- @tparam {[string]=number,...} subject_map Mapping of constraint keys to term coefficients.
function P:add_constraint_term(objective_key, subject_map)
    local term = self.subject_terms[objective_key] or {}
    for k, v in pairs(subject_map) do
        assert(not term[k])
        term[k] = v
    end
    self.subject_terms[objective_key] = term
end

--- Make a vector of the coefficient of the primal problem.
-- @treturn Matrix Coefficients in vector form.
function P:make_primal_coefficients()
    local ret = Matrix.new_vector(self.primal_length)
    for _, v in pairs(self.primal) do
        ret[v.index][1] = v.value
    end
    return ret
end

--- Make a vector of the coefficient of the dual problem.
-- @treturn Matrix Coefficients in vector form.
function P:make_dual_coefficients()
    local ret = Matrix.new_vector(self.dual_length)
    for _, v in pairs(self.dual) do
        ret[v.index][1] = v.value
    end
    return ret
end

--- Make a sparse matrix of constraint equations.
-- @treturn SparseMatrix Constraint equations in matrix form.
function P:make_subject_sparse_matrix()
    local ret = SparseMatrix(self.dual_length, self.primal_length)
    for p, t in pairs(self.subject_terms) do
        if self.primal[p] then
            local x = self.primal[p].index
            for d, v in pairs(t) do
                if self.dual[d] then
                    local y = self.dual[d].index
                    ret:set(y, x, v)
                end
            end
        end
    end
    return ret
end

--- Make a matrix of constraint equations.
-- @treturn Matrix Constraint equations in matrix form.
function P:make_subject_matrix()
    return self:make_subject_sparse_matrix():to_matrix()
end

--- Remove unnecessary variables from the solution of the problem.
-- @tparam Matrix vector Solution to the primal problem.
-- @treturn table Filtered solution.
function P:filter_solution_to_result(vector)
    local ret = {}
    for k, v in pairs(self.primal) do
        if v.is_result then
            ret[k] = vector[v.index][1]
        end
    end
    return ret
end

--- Put primal variables in readable format.
-- @tparam Matrix vector Variables to the primal problem.
-- @treturn string Readable text.
function P:dump_primal(vector)
    local ret = ""
    for k, v in pairs(self.primal) do
        ret = ret .. string.format("%q = %f\n", k, vector[v.index][1])
    end
    return ret
end

--- Put dual variables in readable format.
-- @treturn string Readable text.
function P:dump_dual(vector)
    local ret = ""
    for k, v in pairs(self.dual) do
        ret = ret .. string.format("%q = %f\n", k, vector[v.index][1])
    end
    return ret
end

return C.class("Problem", P, S)
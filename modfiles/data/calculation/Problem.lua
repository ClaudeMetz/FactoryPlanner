local P, S = {}, {}
local C = require("data.calculation.class")
local Matrix = require("data.calculation.Matrix")
local SparseMatrix = require("data.calculation.SparseMatrix")

function P:__new(name)
    self.name = name
    self.primal = {}
    self.primal_length = 0
    self.dual = {}
    self.dual_length = 0
    self.subject_terms = {}
end

function P:add_objective(key, penalty, is_result)
    assert(not self.primal[key])
    self.primal_length = self.primal_length + 1
    self.primal[key] = {
        key = key,
        index = self.primal_length,
        value = penalty or 1,
        is_result = is_result or false,
    }
end

function P:is_exist_objective(key)
    return self.primal[key] ~= nil
end

function P:add_objective_penalty(key, penalty)
    assert(self.primal[key])
    self.primal[key].value = self.primal[key].value + penalty
end

function P:add_eq_constraint(key, limit)
    assert(not self.dual[key])
    self.dual_length = self.dual_length + 1
    self.dual[key] = {
        key = key,
        index = self.dual_length,
        value = limit or 0,
    }
end

function P:add_le_constraint(key, limit)
    local slack_key = "<slack>" .. key
    self:add_eq_constraint(key, limit)
    self:add_objective(slack_key, 0, false)
    self:add_subject_term(slack_key, {
        [key] = 1,
    })
end

function P:add_ge_constraint(key, limit)
    local slack_key = "<slack>" .. key
    self:add_eq_constraint(key, limit)
    self:add_objective(slack_key, 0, false)
    self:add_subject_term(slack_key, {
        [key] = -1,
    })
end

function P:is_exist_constraint(key)
    return self.dual[key] ~= nil
end

function P:add_subject_term(objective_key, constraint_map)
    local term = self.subject_terms[objective_key] or {}
    for k, v in pairs(constraint_map) do
        assert(not term[k])
        term[k] = v
    end
    self.subject_terms[objective_key] = term
end

function P:make_primal_factors()
    local ret = Matrix.new_vector(self.primal_length)
    for _, v in pairs(self.primal) do
        ret[v.index][1] = v.value
    end
    return ret
end

function P:make_dual_factors()
    local ret = Matrix.new_vector(self.dual_length)
    for _, v in pairs(self.dual) do
        ret[v.index][1] = v.value
    end
    return ret
end

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

function P:make_subject_matrix()
    return self:make_subject_sparse_matrix():to_matrix()
end

function P:convert_result(vector)
    local ret = {}
    for k, v in pairs(self.primal) do
        if v.is_result then
            ret[k] = vector[v.index][1]
        end
    end
    return ret
end

function P:dump_primal(vector)
    local ret = ""
    for k, v in pairs(self.primal) do
        ret = ret .. string.format("%q = %f\n", k, vector[v.index][1])
    end
    return ret
end

function P:dump_dual(vector)
    local ret = ""
    for k, v in pairs(self.dual) do
        ret = ret .. string.format("%q = %f\n", k, vector[v.index][1])
    end
    return ret
end

return C.class("Problem", P, S)
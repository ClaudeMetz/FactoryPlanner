local P, S = {}, {}
local C = require("data.calculation.class")

function P:__new(height, width)
    self.height = height
    self.width = width
    for y = 1, height do
        self[y] = {}
    end
end

function S.new_vector(degree)
    return S(degree, 1)
end

function S.list_to_vector(list)
    local ret = S.new_vector(#list)
    for i, v in ipairs(list) do
        ret[i][1] = v
    end
    return ret
end

function S.join(matrixes)
    local heights, widths = {}, {}
    for y, t in ipairs(matrixes) do
        assert(#matrixes[1] == #t)
        for x, v in ipairs(t) do
            if S.is_matrix(v) then
                if not heights[y] then
                    heights[y] = v.height
                else
                    assert(heights[y] == v.height)
                end
                if not widths[x] then
                    widths[x] = v.width
                else
                    assert(widths[x] == v.width)
                end
            else
                assert(type(v) == "number")
            end
        end
    end
    
    local total_height, total_width = 0, 0
    for i = 1, #matrixes do
        heights[i] = heights[i] or 1
        total_height = total_height + heights[i]
    end
    for i = 1, #matrixes[1] do
        widths[i] = widths[i] or 1
        total_width = total_width + widths[i]
    end
    
    local ret = S(total_height, total_width)
    local y_offset = 0
    for oy, t in ipairs(matrixes) do
        local x_offset = 0
        for ox, m in ipairs(t) do
            if S.is_matrix(m) then
                for y = 1, m.height do
                    for x = 1, m.width do
                        ret[y + y_offset][x + x_offset] = m[y][x]
                    end
                end
            else
                assert(m == 0 or widths[ox] == heights[oy])
                for y = 1, heights[oy] do
                    for x = 1, widths[ox] do
                        if y == x then
                            ret[y + y_offset][x + x_offset] = m
                        else
                            ret[y + y_offset][x + x_offset] = 0
                        end
                    end
                end
            end
            x_offset = x_offset + widths[ox]
        end
        y_offset = y_offset + heights[oy]
    end
    return ret
end

function S.join_vector(vectors)
    local matrixes = {}
    for i, v in ipairs(vectors) do
        matrixes[i] = {v}
    end
    return S.join(matrixes)
end

function S.is_matrix(value)
    return C.class_type(value) == C.class_type(S)
end

function P:clone()
    local height, width = self.height, self.width
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = self[y][x]
        end
    end
    return ret
end

function P:fill(value)
    local height, width = self.height, self.width
    for y = 1, height do
        for x = 1, width do
            self[y][x] = value
        end
    end
    return self
end

function P.__add(op1, op2)
    assert(S.is_matrix(op1) and S.is_matrix(op2))
    assert(op1.height == op2.height and op1.width == op2.width)
    local height, width = op1.height, op1.width
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = op1[y][x] + op2[y][x]
        end
    end
    return ret
end

function P.__sub(op1, op2)
    assert(S.is_matrix(op1) and S.is_matrix(op2))
    assert(op1.height == op2.height and op1.width == op2.width)
    local height, width = op1.height, op1.width
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = op1[y][x] - op2[y][x]
        end
    end
    return ret
end

function P.__mul(op1, op2)
    local function mul_scalar(m, s)
        local height, width = m.height, m.width
        local ret = S(height, width)
        for y = 1, height do
            for x = 1, width do
                ret[y][x] = m[y][x] * s
            end
        end
        return ret
    end
    
    if type(op1) == "number" then
        return mul_scalar(op2, op1)
    elseif type(op2) == "number" then
        return mul_scalar(op1, op2)
    elseif S.is_matrix(op1) and S.is_matrix(op2) then
        assert(op1.width == op2.height)
        local l, height, width = op1.width, op1.height, op2.width
        local ret = S(height, width)
        for y = 1, height do
            for x = 1, width do
                local v = 0
                for r = 1, l do
                    v = v + op1[y][r] * op2[r][x]
                end
                ret[y][x] = v
            end
        end
        return ret
    else
        assert()
    end
end

function P.__div(op1, op2)
    if type(op1) == "number" then
        local height, width = op2.height, op2.width
        local ret = S(height, width)
        for y = 1, height do
            for x = 1, width do
                ret[y][x] = op1 / op2[y][x]
            end
        end
        return ret
    elseif type(op2) == "number" then
        local height, width = op1.height, op1.width
        local ret = S(height, width)
        for y = 1, height do
            for x = 1, width do
                ret[y][x] = op1[y][x] / op2
            end
        end
        return ret
    else
        assert()
    end
end

function P:__unm()
    local height, width = self.height, self.width
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = -self[y][x]
        end
    end
    return ret
end

function S.hadamard_product(op1, op2)
    assert(S.is_matrix(op1) and S.is_matrix(op2))
    assert(op1.height == op2.height and op1.width == op2.width)
    local height, width = op1.height, op1.width
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = op1[y][x] * op2[y][x]
        end
    end
    return ret
end

function P:T()
    local height, width = self.width, self.height
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = self[x][y]
        end
    end
    return ret
end

function P:diag()
    local height, width = self.height, self.width
    assert(width == 1)
    local size = height
    local ret = S(size, size):fill(0)
    for i = 1, size do
        ret[i][i] = self[i][1]
    end
    return ret
end

function P:inv_diag()
    local height, width = self.height, self.width
    assert(width == 1)
    local size = height
    local ret = S(size, size):fill(0)
    for i = 1, size do
        ret[i][i] = 1 / self[i][1]
    end
    return ret
end

function P:sum()
    local height, width = self.height, self.width
    assert(width == 1)
    local ret = 0
    for i = 1, height do
        ret = ret + self[i][1]
    end
    return ret
end

function P:euclidean_norm()
    local height, width = self.height, self.width
    assert(width == 1)
    local ret = 0
    for i = 1, height do
        ret = ret + self[i][1] ^ 2
    end
    return math.sqrt(ret)
end

function P:submatrix(top, left, bottom, right)
    local height, width = 1 + bottom - top, 1 + right - left
    local ret = S(height, width)
    for y = 1, height do
        for x = 1, width do
            ret[y][x] = self[top + y - 1][left + x - 1]
        end
    end
    return ret
end

function P:insert_column(vector, x)
    self.width = self.width + 1
    x = x or self.width
    if type(vector) == "number" then
        local v = vector
        for y = 1, self.height do
            table.insert(self[y], x, v)
        end
    else
        assert(S.is_matrix(vector) and vector.width == 1)
        for y = 1, self.height do
            table.insert(self[y], x, vector[y][1])
        end
    end
    return self
end

function P:row_swap(a, b)
    self[a], self[b] = self[b], self[a]
    return self
end

function P:row_mul(y, factor)
    if factor == 0 then
        return self
    end
    for x, v in ipairs(self[y]) do
        self[y][x] = v * factor
    end
    return self
end

function P:row_sum(to, from, factor)
    assert(to ~= from)
    if factor == 0 then
        return self
    end
    factor = factor or 1
    for x, v in ipairs(self[from]) do
        self[to][x] = self[to][x] + v * factor
    end
    return self
end

function P:gaussian_elimination(flee_value)
    flee_value = flee_value or 0
    local height = self.height
    local aug_index = self.width
    assert(height + 1 == aug_index)

    local function select_pivot(c)
        local max_index, max_value = nil, 0
        for y = c, height do
            local v = math.abs(self[y][c])
            if max_value < v then
                max_value = v
                max_index = y
            end
        end
        return max_index
    end

    for i = 1, height do
        local p = select_pivot(i)
        if p then
            self:row_swap(i, p)
            local f = self[i][i]
            self:row_mul(i, 1 / f)
            for k = i + 1, height do
                local g = self[k][i]
                self:row_sum(k, i, -g)
            end
        end
    end

    for i = height, 1, -1 do
        if self[i][i] == 0 then
            self[i][i] = 1
            self[i][aug_index] = flee_value
        end
        for k = 1, i - 1 do
            local g = self[k][i]
            self:row_sum(k, i, -g)
        end
    end

    return self:submatrix(1, aug_index, height, aug_index)
end

return C.class("Matrix", P, S)

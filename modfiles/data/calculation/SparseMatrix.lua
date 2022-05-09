local P, S = {}, {}
local C = require("data.calculation.class")
local Matrix = require("data.calculation.Matrix")

function P:__new(height, width)
    self.height = height
    self.width = width
    self.values = {}
    self.indexes = {}
    for y = 1, height do
        self.values[y] = {}
        self.indexes[y] = {}
    end
end

function S.diag(vector)
    assert(vector.width == 1)
    local size = vector.height
    local ret = S(size, size)
    for i = 1, size do
        ret:set(i, i, vector[i][1])
    end
    return ret
end

function S.join(matrixes)
    local heights, widths = {}, {}
    for y, t in ipairs(matrixes) do
        assert(#matrixes[1] == #t)
        for x, v in ipairs(t) do
            if S.is_sparse_matrix(v) then
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
            if S.is_sparse_matrix(m) then
                for y = 1, m.height do
                    local values = m.values[y]
                    for rx, x in ipairs(m.indexes[y]) do
                        table.insert(ret.values[y + y_offset], values[rx])
                        table.insert(ret.indexes[y + y_offset], x + x_offset)
                    end
                end
            elseif m ~= 0 then
                assert(widths[ox] == heights[oy])
                local size = heights[oy]
                for i = 1, size do
                    table.insert(ret.values[i + y_offset], m)
                    table.insert(ret.indexes[i + y_offset], i + x_offset)
                end
            end
            x_offset = x_offset + widths[ox]
        end
        y_offset = y_offset + heights[oy]
    end
    return ret
end

function S.is_sparse_matrix(value)
    return C.class_type(value) == C.class_type(S)
end

function P:to_matrix()
    local height, width = self.height, self.width
    local ret = Matrix(height, width):fill(0)
    for y = 1, height do
        local values = self.values[y]
        for rx, v in ipairs(self.indexes[y]) do
            ret[y][v] = values[rx]
        end
    end
    return ret
end

function P:clone()
    local height, width = self.height, self.width
    local ret = S(height, width)
    for y = 1, height do
        for rx, v in ipairs(self.values[y]) do
            ret.values[y][rx] = v
        end
        for rx, v in ipairs(self.indexes[y]) do
            ret.indexes[y][rx] = v
        end
    end
    return ret
end

function P.__mul(op1, op2)
    local function mul_scalar(m, s)
        local height, width = m.height, m.width
        local ret = S(height, width)
        for y = 1, height do
            for rx, v in ipairs(m.values[y]) do
                ret.values[y][rx] = v * s
            end
            for rx, v in ipairs(m.indexes[y]) do
                ret.indexes[y][rx] = v
            end
        end
        return ret
    end
    
    if type(op1) == "number" then
        return mul_scalar(op2, op1)
    elseif type(op2) == "number" then
        return mul_scalar(op1, op2)
    elseif S.is_sparse_matrix(op1) and Matrix.is_matrix(op2) then
        assert(op1.width == op2.height)
        local height, width = op1.height, op2.width
        local ret = Matrix(height, width)
        for y = 1, height do
            for x = 1, width do
                local op1_row_indexes, op1_row_values = op1.indexes[y], op1.values[y]
                local v = 0
                for rx, r in ipairs(op1_row_indexes) do
                    v = v + op1_row_values[rx] * op2[r][x]
                end
                ret[y][x] = v
            end
        end
        return ret
    elseif Matrix.is_matrix(op1) and S.is_sparse_matrix(op2) then
        assert(op1.width == op2.height)
        local height, width = op1.height, op2.width
        local op2_t = op2:T()
        local ret = Matrix(height, width)
        for y = 1, height do
            for x = 1, width do
                local op2_column_indexes, op2_column_values = op2_t.indexes[x], op2_t.values[x]
                local v = 0
                for ry, r in ipairs(op2_column_indexes) do
                    v = v + op1[y][r] * op2_column_values[ry]
                end
                ret[y][x] = v
            end
        end
        return ret
    elseif S.is_sparse_matrix(op1) and S.is_sparse_matrix(op2) then
        assert(op1.width == op2.height)
        local height, width = op1.height, op2.width
        local op2_t = op2:T()
        local ret = S(height, width)
        for y = 1, height do
            local ret_indexes, ret_values = ret.indexes[y], ret.values[y]
            for x = 1, width do
                local op1_row_indexes, op1_row_values = op1.indexes[y], op1.values[y]
                local op2_column_indexes, op2_column_values = op2_t.indexes[x], op2_t.values[x]
                local ry, rx = 1, 1
                local function get_x()
                    return op1_row_indexes[rx] or math.huge, op2_column_indexes[ry] or math.huge
                end

                local v = 0
                local op1_r, op2_r = get_x()
                while not (op1_r == math.huge and op2_r == math.huge) do
                    if op1_r < op2_r then
                        rx = rx + 1
                    elseif op1_r > op2_r then
                        ry = ry + 1
                    else -- op1_r == op2_r
                        v = v + op1_row_values[rx] * op2_column_values[ry]
                        rx = rx + 1
                        ry = ry + 1
                    end
                    op1_r, op2_r = get_x()
                end
                if v ~= 0 then
                    table.insert(ret_values, v)
                    table.insert(ret_indexes, x)
                end
            end
        end
        return ret
    else
        assert()
    end
end

function P:__unm()
    return self:__mul(-1)
end

function P:T()
    local height, width = self.width, self.height
    local ret = S(height, width)
    for x = 1, width do
        local values = self.values[x]
        for rx, y in ipairs(self.indexes[x]) do
            table.insert(ret.values[y], values[rx])
            table.insert(ret.indexes[y], x)
        end
    end
    return ret
end

function P:get_raw_index(y, x)
    local indexes = self.indexes[y]
    if x > self.width then
        return #indexes + 1
    end
    for rx, v in ipairs(indexes) do
        if x <= v then
            return rx, x == v
        end
    end
    return #indexes + 1
end

function P:insert_column(vector, x)
    x = x or self.width + 1
    if type(vector) == "number" then
        local value = vector
        for y = 1, self.height do
            self:set(y, x, value)
        end
    else
        assert(Matrix.is_matrix(vector) and vector.width == 1)
        for y = 1, self.height do
            self:set(y, x, vector[y][1])
        end
    end
    self.width = self.width + 1
    return self
end

function P:remove_column(x)
    x = x or self.width
    local ret = {}
    for y = 1, self.height do
        local rx, e = self:get_raw_index(y, x)
        if e then
            local values, indexes = self.values[y], self.indexes[y]
            ret[y] = values[rx]
            table.remove(values, rx)
            table.remove(indexes, rx)
        else
            ret[y] = 0
        end
    end
    self.width = self.width - 1
    return Matrix.list_to_vector(ret)
end

function P:get(y, x)
    local rx, e = self:get_raw_index(y, x)
    if e then
        return self.values[y][rx]
    else
        return 0
    end
end

function P:set(y, x, value)
    local rx, e = self:get_raw_index(y, x)
    if e then
        if value ~= 0 then
            self.values[y][rx] = value
        else
            table.remove(self.values[y], rx)
            table.remove(self.indexes[y], rx)
        end
    elseif value ~= 0 then
        table.insert(self.values[y], rx, value)
        table.insert(self.indexes[y], rx, x)
    end
end

function P:iterate_row(y)
    local values, indexes = self.values[y], self.indexes[y]
    local rx = 0
    local function it()
        rx = rx + 1
        return indexes[rx], values[rx]
    end
    return it
end

function P:row_swap(a, b)
    self.values[a], self.values[b] = self.values[b], self.values[a]
    self.indexes[a], self.indexes[b] = self.indexes[b], self.indexes[a]
    return self
end

function P:row_mul(y, factor)
    local values = self.values[y]
    for rx, v in ipairs(values) do
        values[rx] = v * factor
    end
    return self
end

function P:row_trans(to, from, factor)
    assert(to ~= from)
    if factor == 0 then
        return self
    end
    factor = factor or 1
    local to_values, to_indexes, to_rx = self.values[to], self.indexes[to], 1
    local from_values, from_indexes, from_rx = self.values[from], self.indexes[from], 1
    local new_values, new_indexes = {}, {}
    local function get_x()
        return to_indexes[to_rx] or math.huge, from_indexes[from_rx] or math.huge
    end

    local to_x, from_x = get_x()
    while not (to_x == math.huge and from_x == math.huge) do
        if to_x < from_x then
            local v = to_values[to_rx]
            table.insert(new_values, v)
            table.insert(new_indexes, to_x)
            to_rx = to_rx + 1
        elseif to_x > from_x then
            local v = from_values[from_rx] * factor
            table.insert(new_values, v)
            table.insert(new_indexes, from_x)
            from_rx = from_rx + 1
        else -- to_x == from_x
            local v = to_values[to_rx] + from_values[from_rx] * factor
            if v ~= 0 then
                table.insert(new_values, v)
                table.insert(new_indexes, to_x)
            end
            to_rx = to_rx + 1
            from_rx = from_rx + 1
        end
        to_x, from_x = get_x()
    end
    self.values[to], self.indexes[to] = new_values, new_indexes
    return self
end

return C.class("SparseMatrix", P, S)
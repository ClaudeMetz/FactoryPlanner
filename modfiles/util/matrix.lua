local matrix = {}


--- Subtracts `m[j]` from `m[i]` after scaling with `k`
--- (`m[i] = m[i] - k * m[j]`)
---@param m number[][]
---@param i integer
---@param j integer
---@param k number
function matrix.row_subtract(m, i, j, k)
    if not m[i] or not m[j] then return end
    if k == 0 then return end
    local cols = math.min(#m[i], #m[j])
    for n = 1, cols do
        m[i][n] = m[i][n]--[[@as number]] - k * m[j][n]--[[@as number]]
    end
end


return matrix

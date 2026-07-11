---@namespace Simplex


---@class SimplexTableau
---@field _matrix number[][]
---@field _rows table<string, integer> constraints
---@field _cols table<string, integer> variables
---@field _signs table<string, 1 | -1> variable signs
---@field _basis string[]
local SimplexTableau = {}
SimplexTableau.__index = SimplexTableau


local N = 1e100  -- big number


---@return SimplexTableau
function SimplexTableau:init()
    local instance = {
        _matrix = {{}},
        _rows = {objective = 1},
        _cols = {},
        _basis = {},
        _signs = {}
    }

    setmetatable(instance, self)
    ---@cast instance SimplexTableau
    return instance
end


--- Adds a column representing the line recipe.
--- Missing items are automatically added.
---@param line_data LineData
function SimplexTableau:add_line_variable(line_data)
    local line_key = "line_" .. line_data.line_id

    -- Line is already present in the tableau
    if self._cols[line_key] then return end

    local col_index = self:_add_column(line_key)

    ---@param items ItemList
    ---@param sign 1 | -1
    local function add_rows(items, sign)
        for item, value in pairs(items) do
            local item_key = "item_" .. item
            local row_index = 0

            -- Add the item to the tableau if not already present
            if not self._rows[item_key] then
                row_index = self:_add_row(item_key)
            else
                row_index = self._rows[item_key]
            end

            local coef = self._matrix[row_index]--[[@cast -nil]][col_index] or 0
            self._matrix[row_index]--[[@cast -nil]][col_index] = coef + sign * value
        end
    end

    -- Populate the tableau matrix with the line results
    add_rows(line_data.products, 1)
    add_rows(line_data.ingredients, -1)

end


--- Adds a slack
---@param key PrototypeName
---@param sign? 1 | -1
---@param score? number
function SimplexTableau:add_item_variable(key, sign, score)
    sign = sign or 1  -- default to positive variable
    score = score or 0  -- default to not influence the objective function

    local item_key = "item_" .. key

    -- Item variable is already present in the tableau
    if self._cols[item_key] then return end

    -- Check that the item constraint is present in the tableau
    local row_index = self._rows[item_key] or 0
    if not self._matrix[row_index] then return end

    local col_index = self:_add_column(item_key, sign)
    self._matrix[row_index][col_index] = -sign  -- slack coefficient is opposite to variable
    self._matrix[1]--[[@cast -nil]][col_index] = -score  -- score coefficient is opposite in the tableau
end


---@param key string
---@return integer index
function SimplexTableau:_add_row(key)
    local row_index = #self._matrix + 1
    self._rows[key] = row_index
    self._matrix[row_index] = {}

    for i = 1, #self._matrix[1] do
        self._matrix[row_index][i] = 0
    end

    return row_index
end


---@private
---@param key string
---@param sign? 1 | -1
---@return integer index
function SimplexTableau:_add_column(key, sign)
    sign = sign or 1  -- default to positive variable
    local col_index = #self._matrix[1] + 1
    self._cols[key] = col_index
    self._signs[key] = sign

    for i = 1, #self._matrix do
        self._matrix[i][col_index] = 0
    end

    return col_index
end


return SimplexTableau

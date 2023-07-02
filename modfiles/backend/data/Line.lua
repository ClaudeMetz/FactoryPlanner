local Object = require("backend.data.Object")

---@class Line: Object, ObjectMethods
---@field parent Floor
---@field recipe Recipe
local Line = Object.methods()
Line.__index = Line
script.register_metatable("Line", Line)

---@return Line
local function init()
    local object = Object.init({
        recipe = nil,
    }, "Line", Line)  --[[@as Line]]
    return object
end

return {init = init--[[ , unpack = unpack ]]}

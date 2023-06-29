local Object = require("backend.data.Object")

---@class Floor: Object, ObjectMethods
---@field parent Factory
---@field level integer
---@field first_line Line
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@return Floor
local function init()
    local object = Object.init({
        level = nil,
        first_line = nil,
    }, "Floor", Floor)  --[[@as Floor]]
    return object
end

return init

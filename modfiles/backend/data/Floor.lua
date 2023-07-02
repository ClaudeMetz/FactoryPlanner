local Object = require("backend.data.Object")

---@class Floor: Object, ObjectMethods
---@field class "Floor"
---@field parent Factory
---@field level integer
---@field first_line Line?
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@return Floor
local function init(level)
    local object = Object.init({
        level = level,
        first_line = nil,
    }, "Floor", Floor)  --[[@as Floor]]
    return object
end


---@class PackedFloor: PackedObject
---@field class "Floor"
---@field level integer
---@field first_line Line?

---@return PackedFloor packed_self
function Floor:pack()
    return {}
end

---@param packed_self PackedFloor
---@return Floor floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.level)
    return unpacked_self
end

---@return boolean valid
function Floor:validate()
    return true
end

---@param player LuaPlayer
function Floor:repair(player)

end

return {init = init, unpack = unpack}

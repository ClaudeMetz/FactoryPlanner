local Object = require("backend.data.Object")

---@alias ProductionType "input" | "output"

---@class Line: Object, ObjectMethods
---@field class "Line"
---@field parent Floor
---@field recipe_proto FPRecipePrototype | FPPackedPrototype
---@field production_type ProductionType
---@field first_product SimpleItem?
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field energy_consumption number
---@field pollution number
local Line = Object.methods()
Line.__index = Line
script.register_metatable("Line", Line)

---@return Line
local function init(recipe_proto, production_type)
    local object = Object.init({
        recipe_proto = recipe_proto,
        production_type = production_type,

        first_product = nil,
        first_byproduct = nil,
        first_ingredient = nil,
        energy_consumption = 0,
        pollution = 0,
    }, "Line", Line)  --[[@as Line]]
    return object
end


function Line:index()
    OBJECT_INDEX[self.id] = self
end

function Line:cleanup()
    OBJECT_INDEX[self.id] = nil
end


---@param item_category SimpleItemCategory
---@return fun(): SimpleItem?
function Line:item_iterator(item_category)
    return self:_iterator(self["first_" .. item_category])
end


-- Checks whether the given recipe's products are used on the given floor
-- The triple loop is crappy, but it's the simplest way to check
local function check_product_compatibiltiy(floor, recipe_proto)
    for _, product in pairs(recipe_proto.products) do
        for line in floor:iterator() do
            for ingredient in line:item_iterator("ingredient") do
                if ingredient.proto.type == product.type and ingredient.proto.name == product.name then
                    return true
                end
            end
        end
    end
    return false
end

function Line:paste(object)
    if object.class == "Line" or object.class == "Floor" then
        if self.parent.level > 1 then  -- make sure the recipe is allowed on this floor
            local relevant_line = (object.class == "Floor") and object.first_line or object
            if not check_product_compatibiltiy(self.parent, relevant_line.recipe_proto) then
                return false, "recipe_irrelevant"  -- found no use for the recipe's products
            end
        end

        self.parent:replace(self, object)
        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@class PackedLine: PackedObject
---@field class "Line"
---@field recipe_proto FPPackedPrototype
---@field production_type ProductionType

---@return PackedLine packed_self
function Line:pack()
    return {
        class = self.class,
        recipe_proto = prototyper.util.simplify_prototype(self.recipe_proto, nil),
        production_type = self.production_type
    }
end

---@param packed_self PackedLine
---@return Line floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.recipe_proto, packed_self.production_type)


    return unpacked_self
end

---@return boolean valid
function Line:validate()
    self.recipe_proto = prototyper.util.validate_prototype_object(self.recipe_proto, nil)
    self.valid = (not self.recipe_proto.simplified)


    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Line:repair(player)
    -- An invalid recipe_proto is unrepairable and means this line should be removed
    if self.recipe_proto.simplified then return false end


    self.valid = true
    return self.valid
end

return {init = init, unpack = unpack}

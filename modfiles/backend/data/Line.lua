local Object = require("backend.data.Object")

---@alias ProductionType "input" | "output"

---@class Line: Object, ObjectMethods
---@field class "Line"
---@field parent Floor
---@field recipe_proto FPRecipePrototype | FPPackedPrototype
---@field production_type ProductionType
---@field done boolean
---@field active boolean
---@field percentage number
---@field priority_product (FPItemPrototype | FPPackedPrototype)?
---@field comment string
---@field effects_tooltip LocalisedString
---@field first_product SimpleItem?
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field power number
---@field pollution number
local Line = Object.methods()
Line.__index = Line
script.register_metatable("Line", Line)

---@return Line
local function init(recipe_proto, production_type)
    local object = Object.init({
        recipe_proto = recipe_proto,
        production_type = production_type,
        done = false,
        active = false,
        percentage = 100,
        priority_product = nil,  -- set by the user
        comment = "",

        effects_tooltip = "",  -- TODO
        first_product = nil,
        first_byproduct = nil,
        first_ingredient = nil,
        power = 0,
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
    return self:_iterator(nil, self["first_" .. item_category])
end

---@param item_category SimpleItemCategory
---@param filter ObjectFilter
function Line:find_item(item_category, filter)
    return self:_find(filter, self["first_" .. item_category])
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Line:paste(object)
    if object.class == "Line" or object.class == "Floor" then
        ---@cast object LineObject
        if not self.parent:check_product_compatibility(object) then
            return false, "recipe_irrelevant"  -- found no use for the recipe's products
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
---@field done boolean
---@field active boolean
---@field percentage number
---@field priority_product FPPackedPrototype?
---@field comment string

---@return PackedLine packed_self
function Line:pack()
    return {
        class = self.class,
        recipe_proto = prototyper.util.simplify_prototype(self.recipe_proto, nil),
        production_type = self.production_type,
        done = self.done,
        active = self.active,
        percentage = self.percentage,
        priority_product = prototyper.util.simplify_prototype(self.priority_product, "type"),
        comment = self.comment
    }
end

---@param packed_self PackedLine
---@return Line floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.recipe_proto, packed_self.production_type)
    unpacked_self.done = packed_self.done
    unpacked_self.active = packed_self.active
    unpacked_self.percentage = packed_self.percentage
    -- The prototype will be automatically unpacked by the validation process
    unpacked_self.priority_product = packed_self.priority_product
    unpacked_self.comment = packed_self.comment

    return unpacked_self
end

---@return boolean valid
function Line:validate()
    self.recipe_proto = prototyper.util.validate_prototype_object(self.recipe_proto, nil)
    self.valid = (not self.recipe_proto.simplified)

    if self.priority_product ~= nil then
        self.priority_product = prototyper.util.validate_prototype_object(self.priority_product, "type")
        self.valid = (not self.priority_product.simplified) and self.valid
    end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Line:repair(player)
    -- An invalid recipe_proto is unrepairable and means this line should be removed
    if self.recipe_proto.simplified then return false end

    if self.valid and self.priority_product and self.priority_product.simplified then
        self.priority_product = nil
    end


    self.valid = true
    return self.valid
end

return {init = init, unpack = unpack}

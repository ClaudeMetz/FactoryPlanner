local Object = require("backend.data.Object")
local Floor = require("backend.data.Floor")

---@class Factory: Object, ObjectMethods
---@field parent District
---@field next Factory?
---@field previous Factory?
---@field archived boolean
---@field name string
---@field timescale Timescale
---@field mining_productivity number?
---@field matrix_free_items FPItemPrototype[]?
---@field blueprints string[]
---@field notes string
---@field first_product Item?
---@field top_floor Floor
---@field tick_of_deletion uint?
local Factory = Object.methods()
Factory.__index = Factory
script.register_metatable("Factory", Factory)

---@return Factory
local function init(name, timescale)
    local object = Object.init({
        archived = false,
        --owner = nil,
        --shared = false,
        name = name,
        timescale = timescale,
        mining_productivity = nil,
        matrix_free_items = nil,
        blueprints = {},
        notes = "",
        first_product = nil,
        top_floor = Floor(),

        tick_of_deletion = nil
    }, "Factory", Factory)  --[[@as Factory]]
    object.top_floor.parent = object
    return object
end


---@param item_class "Product" | "Byproduct" | "Ingredient"
---@return function iterator Iterator over all items of the given class
function Factory:iterator(item_class)
    return self:_iterator(self["first_" .. item_class:lower()])
end


---@param attach_products boolean
---@param export_format boolean
---@return LocalisedString caption
---@return LocalisedString? tooltip
function Factory:tostring(attach_products, export_format)
    local caption, tooltip = self.name, nil  -- don't return a tooltip for the export_format

    if attach_products and self.valid then
        local product_string = ""
        for item in self:iterator("Product") do
            product_string = product_string .. "[img=" .. item.proto.sprite .. "]"
        end
        if product_string ~= "" then product_string = product_string .. "  " end
        caption = product_string .. caption
    end

    if not export_format then
        local status_string = ""
        if self.tick_of_deletion then status_string = status_string .. "[img=fp_sprite_trash_red] " end
        if not self.valid then status_string = status_string .. "[img=fp_sprite_warning_red] " end
        caption = status_string .. caption

        local trashed_string = ""  ---@type LocalisedString
        if self.tick_of_deletion then
            local ticks_left_in_trash = self.tick_of_deletion - game.tick
            local minutes_left_in_trash = math.ceil(ticks_left_in_trash / 3600)
            trashed_string = {"fp.subfactory_trashed", minutes_left_in_trash}
        end

        local invalid_string = (not self.valid) and {"fp.subfactory_invalid"} or ""
        tooltip = {"", {"fp.tt_title", caption}, trashed_string, invalid_string}
    end

    return caption, tooltip
end

function Factory:update_product_definitions(new_defined_by)
    for product in self:iterator("Product") do
        local req_amount = product.required_amount
        local current_defined_by = req_amount.defined_by
        if current_defined_by ~= "amount" and new_defined_by ~= current_defined_by then
            req_amount.defined_by = new_defined_by

            local multiplier = (new_defined_by == "belts") and 0.5 or 2
            req_amount.amount = req_amount.amount * multiplier
        end
    end
end

---@return Factory clone
function Factory:clone()
    local clone = self.unpack(self:pack())
    clone.parent = self.parent
    clone:validate()
    return clone
end


---@class PackedFactory

---@return PackedFactory packed_self
function Factory:pack()

end

---@param packed_self PackedFactory
---@return Factory factory
function Factory.unpack(packed_self)

end


---@return boolean valid
function Factory:validate()
    return true
end

return init

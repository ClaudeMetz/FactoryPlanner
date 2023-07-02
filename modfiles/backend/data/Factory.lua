local Object = require("backend.data.Object")
local Floor = require("backend.data.Floor")
local Item = require("backend.data.Item")

---@class Factory: Object, ObjectMethods
---@field class "Factory"
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
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field energy_consumption number
---@field pollution number
---@field tick_of_deletion uint?
---@field item_request_proxy LuaEntity?
---@field linearly_dependant boolean?
---@field last_valid_modset ModToVersion?
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
        top_floor = Floor.init(),

        first_byproduct = nil,
        first_ingredient = nil,
        energy_consumption = 0,
        pollution = 0,
        linearly_dependant = false,
        tick_of_deletion = nil,
        item_request_proxy = nil,
        last_valid_modset = nil
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

---@param new_defined_by "belts" | "lanes"
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


function Factory:validate_item_request_proxy()
    local item_request_proxy = self.item_request_proxy
    if item_request_proxy and (not item_request_proxy.valid or not next(item_request_proxy.item_requests)) then
        self:destroy_item_request_proxy()
    end
end

function Factory:destroy_item_request_proxy()
    self.item_request_proxy.destroy{raise_destroy=false}
    self.item_request_proxy = nil
end


---@class PackedFactory: PackedObject
---@field class "Factory"
---@field name string
---@field timescale Timescale
---@field mining_productivity number?
---@field matrix_free_items FPPackedPrototype[]?
---@field blueprints string[]
---@field notes string
---@field products PackedItem[]?
---@field top_floor PackedFloor

---@return PackedFactory packed_self
function Factory:pack()
    return {
        name = self.name,
        timescale = self.timescale,
        mining_productivity = self.mining_productivity,
        matrix_free_items = prototyper.util.simplify_prototypes(self.matrix_free_items, "type"),
        blueprints = self.blueprints,
        notes = self.notes,
        products = self:_pack(self.first_product),
        top_floor = self.top_floor:pack(),
        class = self.class
    }
end

---@param packed_self PackedFactory
---@return Factory factory
local function unpack(packed_self)
    local unpacked_self = init(packed_self.name, packed_self.timescale)

    unpacked_self.mining_productivity = packed_self.mining_productivity
    -- Item prototypes will be automatically unpacked by the validation process
    unpacked_self.matrix_free_items = packed_self.matrix_free_items
    unpacked_self.blueprints = packed_self.blueprints
    unpacked_self.notes = packed_self.notes

    unpacked_self.first_product = Object.unpack(packed_self.products, Item.unpack, unpacked_self)  --[[@as Item]]
    unpacked_self.top_floor = Floor.unpack(packed_self.top_floor)
    unpacked_self.top_floor.parent = unpacked_self

    return unpacked_self
end


---@return Factory clone
function Factory:clone()
    local clone = unpack(self:pack())
    clone:validate()
    return clone
end


---@return boolean valid
function Factory:validate()
    local previous_validity = self.valid

    self.valid = true
    self.valid = self:_validate(self.first_product) and self.valid
    self.valid = self.top_floor:validate() and self.valid

    local matrix_free_items, valid = prototyper.util.validate_prototype_objects(self.matrix_free_items, "type")
    self.matrix_free_items = matrix_free_items
    self.valid = valid and self.valid

    self:validate_item_request_proxy()  -- makes sure proxy is valid, or deletes it

    if self.valid then self.last_valid_modset = nil
    -- If this subfactory became invalid with the current configuration, retain the modset before the current one
    -- The one in global is still the previous one as it's only updated after migrations
    elseif previous_validity and not self.valid then self.last_valid_modset = global.installed_mods end

    return self.valid
end

---@param player LuaPlayer
function Factory:repair(player)
    self:_repair(self.first_product, player)
    self.top_floor:repair(player)

    -- Remove any unrepairable free items so the factory remains valid
    local free_items = self.matrix_free_items or {}
    for index = #free_items, 1, -1 do
        if free_items[index].simplified --[[@as AnyPrototype]] then
            table.remove(free_items, index)
        end
    end

    self.last_valid_modset = nil
    self.valid = true
end

return {init = init, unpack = unpack}

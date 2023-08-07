local Object = require("backend.data.Object")
local Floor = require("backend.data.Floor")
local Product = require("backend.data.Product")

---@class Factory: Object, ObjectMethods
---@field class "Factory"
---@field parent District
---@field next Factory?
---@field previous Factory?
---@field first Product?
---@field archived boolean
---@field name string
---@field timescale Timescale
---@field mining_productivity number?
---@field matrix_free_items FPItemPrototype[]?
---@field blueprints string[]
---@field notes string
---@field top_floor Floor
---@field linearly_dependant boolean?
---@field tick_of_deletion uint?
---@field item_request_proxy LuaEntity?
---@field last_valid_modset ModToVersion?
local Factory = Object.methods()
Factory.__index = Factory
script.register_metatable("Factory", Factory)

---@param name string
---@param timescale Timescale
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
        top_floor = Floor.init(),

        linearly_dependant = false,
        tick_of_deletion = nil,
        item_request_proxy = nil,
        last_valid_modset = nil
    }, "Factory", Factory)  --[[@as Factory]]
    object.top_floor.parent = object
    return object
end


function Factory:index()
    OBJECT_INDEX[self.id] = self
    for product in self:iterator() do product:index() end
    self.top_floor:index()
end

function Factory:cleanup()
    OBJECT_INDEX[self.id] = nil
    for product in self:iterator() do product:cleanup() end
    self.top_floor:cleanup()
end


---@param product Product
---@param relative_object Product?
---@param direction NeighbourDirection?
function Factory:insert(product, relative_object, direction)
    product.parent = self
    self:_insert(product, relative_object, direction)
end

---@param product Product
function Factory:remove(product)
    product.parent = nil
    product:cleanup()
    self:_remove(product)
end

---@param product Product
---@param new_product Product
function Factory:replace(product, new_product)
    new_product.parent = self
    self:_replace(product, new_product)
end


---@param filter ObjectFilter
---@param pivot Product?
---@param direction NeighbourDirection?
---@return Product? product
function Factory:find(filter, pivot, direction)
    return self:_find(filter, pivot, direction)  --[[@as Product?]]
end


---@param filter ObjectFilter?
---@param pivot Product?
---@param direction NeighbourDirection?
---@return fun(): Product?
function Factory:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param pivot Product?
---@param direction NeighbourDirection?
---@return number count
function Factory:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


---@param attach_products boolean
---@param export_format boolean
---@return LocalisedString caption
---@return LocalisedString? tooltip
function Factory:tostring(attach_products, export_format)
    local caption, tooltip = self.name, nil  -- don't return a tooltip for the export_format

    if attach_products and self.valid then
        local product_string = ""
        for item in self:iterator() do
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


-- Only used when switching between belts and lanes
---@param new_defined_by ProductDefinedBy
function Factory:update_product_definitions(new_defined_by)
    for product in self:iterator() do
        product:update_definition(new_defined_by)
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
---@field products PackedProduct[]?
---@field top_floor PackedFloor

---@return PackedFactory packed_self
function Factory:pack()
    return {
        class = self.class,
        name = self.name,
        timescale = self.timescale,
        mining_productivity = self.mining_productivity,
        matrix_free_items = prototyper.util.simplify_prototypes(self.matrix_free_items, "type"),
        blueprints = self.blueprints,
        notes = self.notes,
        products = self:_pack(self.first),
        top_floor = self.top_floor:pack()
    }
end

---@param packed_self PackedFactory
---@return Factory factory
local function unpack(packed_self)
    local unpacked_self = init(packed_self.name, packed_self.timescale)

    unpacked_self.mining_productivity = packed_self.mining_productivity
    -- Product prototypes will be automatically unpacked by the validation process
    unpacked_self.matrix_free_items = packed_self.matrix_free_items
    unpacked_self.blueprints = packed_self.blueprints
    unpacked_self.notes = packed_self.notes

    local function unpacker(item) return Product.unpack(item) end
    unpacked_self.first = Object.unpack(packed_self.products, unpacker, unpacked_self)  --[[@as Product]]

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

    self.valid = self:_validate(self.first) and self.valid
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
---@return boolean success
function Factory:repair(player)
    self:_repair(self.first, player)
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
    return self.valid
end

return {init = init, unpack = unpack}

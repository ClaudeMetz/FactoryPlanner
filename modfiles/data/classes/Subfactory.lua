-- 'Class' representing a independent part of the factory with in- and outputs
Subfactory = {}

function Subfactory.init(name, icon)
    local subfactory = {
        name = name,
        icon = icon,
        timescale = nil,  -- needs to be set after init
        energy_consumption = 0,
        pollution = 0,
        notes = "",
        mining_productivity = nil,
        Product = Collection.init("Item"),
        Byproduct = Collection.init("Item"),
        Ingredient = Collection.init("Item"),
        Floor = Collection.init("Floor"),
        matrix_free_items = nil,
        linearly_dependant = false,  -- determined by the solver
        selected_floor = nil,
        item_request_proxy = nil,
        tick_of_deletion = nil,  -- ignored on export/import
        last_valid_modset = nil,  -- also ignored for import/export
        valid = true,
        mod_version = global.mod_version,
        class = "Subfactory"
    }

    -- Initialize the subfactory with an empty top floor
    subfactory.selected_floor = Floor.init(nil)
    Subfactory.add(subfactory, subfactory.selected_floor)

    return subfactory
end


-- Returns first whether the icon is missing, then the rich text for it
function Subfactory.verify_icon(self)
    local type = (self.icon.type == "virtual") and "virtual-signal" or self.icon.type
    local subfactory_sprite = type .. "/" .. self.icon.name

    if not game.is_valid_sprite_path(subfactory_sprite) then
        return true, ("[img=utility/missing_icon]")
    else
        return false, ("[img=" .. subfactory_sprite .. "]")
    end
end

function Subfactory.tostring(self, export_format)
    local status_string = ""
    if not export_format then
        if self.tick_of_deletion then status_string = status_string .. "[img=fp_sprite_trash_red] " end
        if not self.valid then status_string = status_string .. "[img=fp_sprite_warning_red]  " end
    end

    local name_string = self.name
    if self.icon then
        local _, sprite_rich_text = Subfactory.verify_icon(self)
        name_string = sprite_rich_text .. "  "
    end

    local tooltip = nil  -- don't return a tooltip for the export_format
    if not export_format then
        local trashed_string = ""
        if self.tick_of_deletion then
            local ticks_left_in_trash = self.tick_of_deletion - game.tick
            local minutes_left_in_trash = math.ceil(ticks_left_in_trash / 3600)
            trashed_string = {"fp.newline", {"fp.subfactory_trashed", minutes_left_in_trash}}
        end

        local invalid_string = (not self.valid) and {"fp.newline", {"fp.subfactory_invalid"}} or ""
        tooltip = {"", name_string, trashed_string, invalid_string}
    end

    local caption = (status_string .. name_string)
    return caption, tooltip
end


function Subfactory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Subfactory.remove(self, dataset)
    return Collection.remove(self[dataset.class], dataset)
end

function Subfactory.clear(self, class)
    self[class] = Collection.clear(self[class])
end


function Subfactory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Subfactory.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

-- Floors don't have an inherent order, so this makes sense for them
function Subfactory.get_all_floors(self)
    return self.Floor.datasets
end

function Subfactory.get_by_name(self, class, name)
    return Collection.get_by_name(self[class], name)
end


function Subfactory.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
end


-- Returns the machines and modules needed to actually build this subfactory
function Subfactory.get_component_data(self)
    local components = {machines={}, modules={}}

    for _, floor in pairs(Floor.get_in_order(self, "Floor")) do
        -- Relies on the floor-function to do the heavy lifting
        Floor.get_component_data(floor, components)
    end

    return components
end


-- Updates every top level product of this Subfactory to the given product definition type
function Subfactory.update_product_definitions(self, new_defined_by)
    for _, product in pairs(Subfactory.get_in_order(self, "Product")) do
        local req_amount = product.required_amount
        local current_defined_by = req_amount.defined_by
        if current_defined_by ~= "amount" and new_defined_by ~= current_defined_by then
            req_amount.defined_by = new_defined_by

            local multiplier = (new_defined_by == "belts") and 0.5 or 2
            req_amount.amount = req_amount.amount * multiplier
        end
    end
end


function Subfactory.validate_item_request_proxy(self)
    local item_request_proxy = self.item_request_proxy
    if item_request_proxy then
        if not item_request_proxy.valid or table_size(item_request_proxy.item_requests) == 0 then
            Subfactory.destroy_item_request_proxy(self)
        end
    end
end

function Subfactory.destroy_item_request_proxy(self)
    self.item_request_proxy.destroy{raise_destroy=false}
    self.item_request_proxy = nil
end


function Subfactory.pack(self)
    local packed_free_items = (self.matrix_free_items) and {} or nil
    for index, proto in pairs(self.matrix_free_items or {}) do
        packed_free_items[index] = prototyper.util.simplify_prototype(proto)
    end

    return {
        name = self.name,
        icon = self.icon,
        timescale = self.timescale,
        notes = self.notes,
        mining_productivity = self.mining_productivity,
        Product = Collection.pack(self.Product),
        matrix_free_items = packed_free_items,
        -- Floors get packed by recursive nesting, which is necessary for a json-type data
        -- structure. It will need to be unpacked into the regular structure 'manually'.
        top_floor = Floor.pack(Subfactory.get(self, "Floor", 1)),
        class = self.class
    }
end

function Subfactory.unpack(packed_self)
    local self = Subfactory.init(packed_self.name, packed_self.icon)

    self.timescale = packed_self.timescale
    self.notes = packed_self.notes
    self.mining_productivity = packed_self.mining_productivity
    self.Product = Collection.unpack(packed_self.Product, self)

    if packed_self.matrix_free_items then
        self.matrix_free_items = {}
        for index, proto in pairs(packed_self.matrix_free_items) do
            -- Prototypes will be automatically unpacked by the validation process
            self.matrix_free_items[index] = proto
        end
    end

    -- Floor unpacking is called on the top floor, which recursively goes through its subfloors
    local top_floor = self.selected_floor
    Floor.unpack(packed_self.top_floor, top_floor)

    return self
end


-- Needs validation: Product, Floor
function Subfactory.validate(self)
    local previous_validity = self.valid

    self.valid = Collection.validate_datasets(self.Product)

    -- Validating matrix_free_items is a bit messy with the current functions,
    -- it might be worth it to change it into a Collection at some point
    for index, _ in pairs(self.matrix_free_items or {}) do
        self.valid = prototyper.util.validate_prototype_object(self.matrix_free_items, index, "items", "type")
          and self.valid
    end

    -- Floor validation is called on the top floor, which recursively goes through its subfloors
    local top_floor = Subfactory.get(self, "Floor", 1)
    self.valid = Floor.validate(top_floor) and self.valid

    Subfactory.validate_item_request_proxy(self)

    if self.valid then self.last_valid_modset = nil
    -- If this subfactory became invalid with the current configuration, retain the modset before the current one
    -- The one in global is still the previous one as it's only updated after migrations
    elseif previous_validity and not self.valid then self.last_valid_modset = global.installed_mods end

    -- return value is not needed here
end

-- Needs repair: Product, Floor, selected_floor
function Subfactory.repair(self, player)
    -- Set selected floor to the top one in case the selected one gets deleted
    local selected_floor = self.selected_floor
    local top_floor = Subfactory.get(self, "Floor", 1)
    ui_util.context.set_floor(player, top_floor)  -- sets selected_floor on this subfactory
    Floor.remove_if_empty(selected_floor)  -- Make sure no empty floor is left behind

    -- Unrepairable item-objects get removed, so the subfactory will always be valid afterwards
    Collection.repair_datasets(self.Product, nil)

    -- Clear item prototypes so we don't need to rely on the solver to remove them
    Subfactory.clear(self, "Byproduct")
    Subfactory.clear(self, "Ingredient")

    -- Remove any unrepairable free item so the subfactory remains valid
    -- (Not sure if this removing-while-iterating actually works)
    local free_items = self.matrix_free_items
    for index, item_proto in pairs(free_items or {}) do
        if item_proto.simplified then table.remove(free_items, index) end
    end

    -- Floor repair is called on the top floor, which recursively goes through its subfloors
    Floor.repair(top_floor, player)

    self.last_valid_modset = nil
    self.valid = true
    -- return value is not needed here
end
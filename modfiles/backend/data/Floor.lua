local Object = require("backend.data.Object")
local Line = require("backend.data.Line")
local SimpleItem = require("backend.data.SimpleItem")

---@alias LineObject Line | Floor
---@alias LineParent Factory | Floor

---@class Floor: Object, ObjectMethods
---@field class "Floor"
---@field parent LineParent
---@field next LineObject?
---@field previous LineObject?
---@field level integer
---@field first LineObject?
---@field products SimpleItem[]
---@field byproducts SimpleItem[]
---@field ingredients SimpleItem[]
---@field machine_amount integer
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@param level integer
---@return Floor
local function init(level)
    local object = Object.init({
        level = level,
        first = nil,

        products = {},
        byproducts = {},
        ingredients = {},
        machine_amount = 0
    }, "Floor", Floor)  ---@as Floor
    return object
end


function Floor:index()
    OBJECT_INDEX[self.id] = self
    for line in self:iterator() do line:index() end
end


---@param line LineObject
---@param relative_object LineObject?
---@param direction NeighbourDirection?
function Floor:insert(line, relative_object, direction)
    line.parent = self
    self:_insert(line, relative_object, direction)
end

---@param line LineObject
---@param preserve boolean?
function Floor:remove(line, preserve)
    line.parent = nil
    self:_remove(line)

    if preserve or self.level == 1 then return end
    ---@cast self.first -nil

    -- Convert floor to line in parent if only defining line remains
    if self.first.next == nil then self.parent:replace(self, self.first) end
end

---@param line LineObject
---@param new_line LineObject
function Floor:replace(line, new_line)
    line.parent = nil
    new_line.parent = self
    self:_replace(line, new_line)
end


---@param line LineObject
---@param direction NeighbourDirection
---@param spots integer?
function Floor:shift(line, direction, spots)
    self:_shift(line, direction, spots)
end


---@return LineObject?
function Floor:find_last()
    return self:_find_last()  ---@as LineObject?
end

---@param filter ObjectFilter?
---@param pivot LineObject?
---@param direction NeighbourDirection?
---@return fun(): LineObject?
function Floor:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param pivot LineObject?
---@param direction NeighbourDirection?
---@return number count
function Floor:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


---@alias ComponentDataSet { proto: LuaItemPrototype, quality_proto: FPQualityPrototype, amount: integer }

---@class ComponentData
---@field machines table<string, ComponentDataSet>
---@field modules table<string, ComponentDataSet>

-- Returns the machines and modules needed to actually build this floor
---@param skip_done boolean
---@param component_table ComponentData?
---@return ComponentData components
function Floor:get_component_data(skip_done, component_table)
    local components = component_table or {machines={}, modules={}}

    ---@param table table<string,ComponentDataSet>
    ---@param item_name string?
    ---@param quality_proto FPQualityPrototype
    ---@param amount integer
    local function add_component(table, item_name, quality_proto, amount)
        if item_name == nil then return end  -- built_by_item_name can be nil
        local proto = prototypes.item[item_name]
        if proto == nil then return end

        local combined_name = item_name .. "-" .. quality_proto.name
        local component = table[combined_name]
        if component == nil then
            table[combined_name] = {proto = proto, quality_proto = quality_proto, amount = amount}
        else
            component.amount = component.amount + amount
        end
    end

    ---@param object Machine | Beacon
    ---@param amount integer
    local function add_machine(object, amount)
        ---@cast object.quality_proto FPQualityPrototype
        add_component(components.machines, object.proto.built_by_item_name, object.quality_proto, amount)

        for module in object.module_set:iterator() do
            ---@cast module.proto FPModulePrototype
            ---@cast module.quality_proto FPQualityPrototype
            add_component(components.modules, module.proto.name, module.quality_proto, amount * module.amount)
        end
    end

    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            line:get_component_data(skip_done, components)

        elseif not skip_done or not line.done then
            local machine = line.machine
            local ceil_machine_amount = math.ceil(machine.amount - MAGIC_NUMBERS.margin_of_error)
            add_machine(machine, ceil_machine_amount)

            local beacon = line.beacon
            if beacon and beacon.total_amount then
                local ceil_total_amount = math.ceil(beacon.total_amount - MAGIC_NUMBERS.margin_of_error)
                add_machine(beacon, ceil_total_amount)
            end
        end
    end

    return components
end


---@return boolean any_found
function Floor:any_lines_not_marked_done()
    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            local result = line:any_lines_not_marked_done()
            if result then return true end
        else
            if not line.done then return true end
        end
    end
    return false
end


---@param object LineObject
---@return boolean compatible
function Floor:check_product_compatibility(object)
    if self.level == 1 then return true end

    local relevant_line = (object.class == "Floor") and object.first or object
    local recipe = relevant_line.recipe  ---@cast recipe -nil
    local producing = (recipe.production_type == "produce")

    -- Use the recipe's net items, as the picker only offers recipes that actually net the
    -- item in question, which the raw prototype items don't take into account
    local relevant_items = producing and recipe.products or recipe.ingredients

    ---@param type string
    ---@param name string
    ---@param base_name string?
    ---@param temperature float?
    ---@return boolean
    local function relevant(type, name, base_name, temperature)
        for _, item in pairs(relevant_items) do
            local item_temperature = producing and item.temperature or recipe:get_temperature(item)
            if item.type == type and (item.name == name or item.name == base_name or item.base_name == name)
                    and item_temperature == temperature then
                return true
            end
        end
        return false
    end

    ---@param items SimpleItem[]
    ---@return boolean
    local function any_relevant(items)
        for _, item in pairs(items) do
            local proto = item.proto
            if relevant(proto.type, proto.name, proto.base_name, proto.temperature) then
                return true
            end
        end
        return false
    end

    for line in self:iterator() do
        if producing then
            -- Check whether any line on this floor consumes something the pasted line produces
            for _, ingredient in pairs(line.ingredients) do
                local proto = ingredient.proto
                -- Subfloors have no recipe to resolve a temperature with, so use the proto's directly
                local temperature = proto.temperature
                if line.recipe then temperature = line.recipe:get_temperature(proto) end
                if relevant(proto.type, proto.name, nil, temperature) then return true end
            end
            local fuel = line.machine and line.machine.fuel
            if fuel and relevant(fuel.proto.elem_type--[[@as string]], fuel.proto.name, nil, fuel.temperature) then
                return true
            end
        else
            -- Check whether any line on this floor produces something the pasted line consumes
            if any_relevant(line.products) or any_relevant(line.byproducts) then return true end
        end
    end

    return false
end

function Floor:reset_surface_compatibility()
    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            line:reset_surface_compatibility()
        else
            line.surface_compatibility = nil
        end
    end
end

---@param object CopyableObject
---@return boolean success
---@return string? error
function Floor:paste(object)
    if object.class == "Line" or object.class == "Floor" then
        if not self:check_product_compatibility(object--[[@as LineObject]]) then
            return false, "recipe_irrelevant"  -- found no use for the recipe's products
        end

        self:insert(object--[[@as LineObject]])
        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@alias PackedLineObject PackedLine | PackedFloor

---@class PackedFloor: PackedObject
---@field class "Floor"
---@field level integer
---@field lines PackedLineObject[]

---@param full boolean
---@return PackedFloor packed_self
function Floor:pack(full)
    return {
        class = self.class,
        level = self.level,
        lines = self:_pack(full),

        products = (full) and SimpleItem.pack_items(self.products) or nil,
        byproducts = (full) and SimpleItem.pack_items(self.byproducts) or nil,
        ingredients = (full) and SimpleItem.pack_items(self.ingredients) or nil,
    }
end

---@param packed_self PackedFloor
---@return Floor floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.level)

    ---@param line PackedLineObject
    ---@return LineObject line
    local function unpacker(line)
        return (line.class == "Floor") and unpack(line--[[@as PackedFloor]]) or Line.unpack(line--[[@as PackedLine]])
    end
    unpacked_self.first = Object.unpack(packed_self.lines, unpacker, unpacked_self)  ---@as LineObject

    return unpacked_self
end


---@param player LuaPlayer
---@return boolean valid
function Floor:validate(player)
    self.valid = self:_validate(player)
    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Floor:repair(player)
    local pivot = self.first
    if self.level > 1 and self.first and not self.first.valid then
        local line_valid = self.first:repair(player)
        -- If the defining line can't be repaired, the floor is dead
        if not line_valid then return false end
        pivot = self.first.next
    end

    if pivot then self:_repair(player, pivot) end
    self.valid = true

    return self.valid
end

return {init = init, unpack = unpack}

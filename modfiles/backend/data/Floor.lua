local Object = require("backend.data.Object")
local Line = require("backend.data.Line")

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


---@alias ComponentDataSet { proto: AnyFPPrototype, quality_proto: FPQualityPrototype, amount: integer }

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
    ---@param proto FPItemPrototype | FPModulePrototype
    ---@param quality_proto FPQualityPrototype
    ---@param amount integer
    local function add_component(table, proto, quality_proto, amount)
        local combined_name = proto.name .. "-" .. quality_proto.name
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
        if object.proto.built_by_item then
            ---@cast object.quality_proto FPQualityPrototype
            add_component(components.machines, object.proto.built_by_item, object.quality_proto, amount)
        end

        for module in object.module_set:iterator() do
            ---@cast module.proto FPModulePrototype
            ---@cast module.quality_proto FPQualityPrototype
            add_component(components.modules, module.proto, module.quality_proto, amount * module.amount)
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


---@param object LineObject
---@return boolean compatible
function Floor:check_product_compatibility(object)
    if self.level == 1 then return true end

    local relevant_line = (object.class == "Floor") and object.first or object
    ---@cast relevant_line.recipe -nil

    -- The triple loop is crappy, but it's the simplest way to check
    if relevant_line.recipe.production_type == "produce" then
        ---@cast relevant_line.recipe.proto.products -nil
        for _, product in pairs(relevant_line.recipe.proto.products) do
            for line in self:iterator() do  ---@cast line.recipe -nil
                -- Check if pasted line produces an ingredient on a line on this floor
                for _, ingredient in pairs(line.ingredients) do
                    if ingredient.proto.type == product.type
                            and (ingredient.proto.name == product.name or ingredient.proto.name == product.base_name)
                            and (line.recipe:get_temperature(ingredient.proto) == product.temperature) then
                        return true
                    end
                end

                -- Check if pasted line produces a fuel on a line on this floor
                if line.machine and line.machine.fuel then
                    local fuel = line.machine.fuel  ---@type Fuel
                    if fuel.proto.elem_type == product.type
                            and (fuel.proto.name == product.name or fuel.proto.name == product.base_name)
                            and (fuel.temperature == product.temperature) then
                        return true
                    end
                end
            end
        end
    end

    -- Check if the pasted line consumes any byproduct of a line on this floor
    if relevant_line.recipe.production_type == "consume" then
        ---@cast relevant_line.recipe.proto.ingredients -nil
        for _, ingredient in pairs(relevant_line.recipe.proto.ingredients) do
            for line in self:iterator() do
                for _, byproduct in pairs(line.byproducts) do
                    if ingredient.type == byproduct.proto.type and
                            (ingredient.name == byproduct.proto.name or ingredient.name == byproduct.proto.base_name)
                            and (relevant_line.recipe:get_temperature(ingredient) == byproduct.proto.temperature) then
                        return true
                    end
                end
            end
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

        self.parent:replace(self, object--[[@as LineObject]])
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

        products = (full) and interface.pack_items(self.products) or nil,
        byproducts = (full) and interface.pack_items(self.byproducts) or nil,
        ingredients = (full) and interface.pack_items(self.ingredients) or nil,
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


---@return boolean valid
function Floor:validate()
    self.valid = self:_validate()
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

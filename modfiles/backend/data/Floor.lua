local Object = require("backend.data.Object")
local Line = require("backend.data.Line")

---@alias LineObject Line | Floor
---@alias LineParent Factory | Floor

---@class Floor: Object, ObjectMethods
---@field class "Floor"
---@field parent LineParent
---@field level integer
---@field first_line LineObject?
---@field first_product SimpleItem?
---@field first_byproduct SimpleItem?
---@field first_ingredient SimpleItem?
---@field energy_consumption number
---@field pollution number
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@return Floor
local function init(level)
    local object = Object.init({
        level = level,
        first_line = nil,

        first_product = nil,
        first_byproduct = nil,
        first_ingredient = nil,
        energy_consumption = 0,
        pollution = 0,
    }, "Floor", Floor)  --[[@as Floor]]
    return object
end


function Floor:index()
    OBJECT_INDEX[self.id] = self
    for line in self:iterator() do line:index() end
end

function Floor:cleanup()
    OBJECT_INDEX[self.id] = nil
    for line in self:iterator() do line:cleanup() end
end


---@param line LineObject
---@param relative_object LineObject?
---@param direction NeighbourDirection?
function Floor:insert(line, relative_object, direction)
    line.parent = self
    self:_insert(line, relative_object, direction)
end

---@param line LineObject
function Floor:remove(line)
    line.parent = nil
    line:cleanup()
    self:_remove(line)

    -- Convert floor to line in parent if only defining line remains
    if self.level > 1 and self.first_line.next == nil then
        local parent_floor = self.parent  --[[@as Floor]]
        parent_floor:insert(self.first_line, self, "next")
        parent_floor:remove(self)
    end
end

---@param line LineObject
---@param new_line LineObject
function Floor:replace(line, new_line)
    new_line.parent = self
    self:_replace(line, line)
end

-- Replace this subfloor with a line in the parent floor
function Floor:reset()
    if self.level == 1 then error("Can't reset the top floor") end
    self.parent:replace(self, self.first_line)
end

---@return LineObject?
function Floor:find_last()
    return self:_find_last(self.first_line)  --[[@as LineObject?]]
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot LineObject?
---@return fun(): LineObject?
function Floor:iterator(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_line)
    return self:_iterator(pivot_object, filter, direction)
end

---@param item_category SimpleItemCategory
---@return fun(): SimpleItem?
function Floor:item_iterator(item_category)
    return self:_iterator(self["first_" .. item_category])
end

---@param filter ObjectFilter?
---@param direction NeighbourDirection?
---@param pivot LineObject?
---@return number count
function Floor:count(filter, direction, pivot)
    local pivot_object = self:_determine_pivot(direction, pivot, self.first_line)
    return self:_count(pivot_object, filter, direction)
end


---@return boolean any_removed
function Floor:remove_consuming_lines()
    local any_removed = false
    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            any_removed = line:remove_consuming_lines() or any_removed
        elseif line.production_type == "consume" then
            self:remove(line)
            any_removed = true
        end
    end
    return any_removed
end


---@alias ComponentDataSet { proto: FPPrototype, amount: number }

---@class ComponentData
---@field machines { [string]: ComponentDataSet}
---@field modules { [string]: ComponentDataSet}

-- Returns the machines and modules needed to actually build this floor
---@param component_table ComponentData?
---@return ComponentData components
function Floor:get_component_data(component_table)
    local components = component_table or {machines={}, modules={}}

    local function add_component(table, proto, amount)
        local component = table[proto.name]
        if component == nil then
            table[proto.name] = {proto = proto, amount = amount}
        else
            component.amount = component.amount + amount
        end
    end

    local function add_machine(entity_proto, amount)
        if not entity_proto.built_by_item then return end
        add_component(components.machines, entity_proto.built_by_item, amount)
    end

    for line in self:iterator() do  -- TODO finish
        --[[ if line.class == "Floor" then
            line:get_component_data(component_table)
        else  -- class == "Line"
            local machine = line.machine
            local ceil_machine_count = math.ceil(machine.count - 0.001)

            add_machine(machine.proto, ceil_machine_count)
            for _, module in pairs(ModuleSet.get_in_order(machine.module_set)) do
                add_component(components.modules, module.proto, ceil_machine_count * module.amount)
            end

            local beacon = line.beacon
            if beacon and beacon.total_amount then
                local ceil_total_amount = math.ceil(beacon.total_amount - 0.001)

                add_machine(beacon.proto, ceil_total_amount)
                for _, module in pairs(ModuleSet.get_all(beacon.module_set)) do
                    add_component(components.modules, module.proto, ceil_total_amount * module.amount)
                end
            end
        end ]]
    end

    return components
end


---@alias PackedLineObject PackedLine | PackedFloor

---@class PackedFloor: PackedObject
---@field class "Floor"
---@field level integer
---@field lines PackedLineObject[]?

---@return PackedFloor packed_self
function Floor:pack()
    return {
        class = self.class,
        level = self.level,
        lines = self:_pack(self.first_line)
    }
end

---@param packed_self PackedFloor
---@return Floor floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.level)

    local function unpacker(line) return (line.class == "Floor") and unpack(line) or Line.unpack(line) end
    unpacked_self.first_line = Object.unpack(packed_self.lines, unpacker, unpacked_self)  --[[@as LineObject]]

    return unpacked_self
end

---@return boolean valid
function Floor:validate()
    self.valid = self:_validate(self.first_line)
    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Floor:repair(player)
    -- TODO check how this works with subfloors, and the first line being invalid
    self:_repair(self.first_line, player)  -- always makes it valid

    self.valid = true
    return self.valid
end

return {init = init, unpack = unpack}

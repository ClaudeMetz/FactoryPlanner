---@class FPFloor
---@field level integer
---@field origin_line FPLine | nil
---@field defining_line FPLine | nil
---@field Line FPCollection<FPLine>
---@field valid boolean
---@field id integer
---@field parent FPSubfactory
---@field class "Floor"

-- 'Class' representing a floor of a subfactory with individual assembly lines
Floor = {}

function Floor.init(creating_line)
    local floor = {
        level = 1,  -- top floor has a level of 1, it's initialized with Floor.init(nil)
        origin_line = nil,  -- set below, only if level > 1. The line this subfloor is attached to
        defining_line = nil,  -- set below, only if level > 1. First line of this subfloor
        Line = Collection.init(),
        valid = true,
        id = nil,  -- set by collection
        parent = nil,  -- set by parent
        class = "Floor"
    }

    -- Move given line, if it exists, to the subfloor, and create a new origin line
    if creating_line ~= nil then
        -- Subfloors have a level that is 1 higher than their creating_line's floor
        floor.level = creating_line.parent.level + 1
        floor.parent = creating_line.parent

        local origin_line = Line.init(nil)  -- No need to set a machine in this case

        origin_line.subfloor = floor  -- Link up the newly created origin_line with its subfloor
        floor.origin_line = origin_line  -- and vice versa

        -- Replace the creating_line on its floor with the newly created origin_line
        Floor.replace(creating_line.parent, creating_line, origin_line)

        Floor.add(floor, creating_line)  -- Add the creating_line to the subfloor in the first spot
        floor.defining_line = creating_line  -- which makes it the defining_line on this floor
    end

    return floor
end


function Floor.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Floor.insert_at(self, gui_position, object)
    object.parent = self
    return Collection.insert_at(self[object.class], gui_position, object)
end


function Floor.remove(self, dataset)
    -- Remove the subfloor(s) associated to a line recursively, so they don't hang around
    if dataset.class == "Line" and dataset.subfloor ~= nil then
        for _, line in pairs(Floor.get_in_order(dataset.subfloor, "Line")) do
            if line.subfloor then Floor.remove(dataset.subfloor, line) end
        end
        Collection.remove(self.parent.Floor, dataset.subfloor)
    end

    return Collection.remove(self[dataset.class], dataset)
end

-- Call only on subfloor; deletes itself while leaving defining_line intact
function Floor.reset(self)
    local origin_line = self.origin_line
    Floor.replace(origin_line.parent, origin_line, self.defining_line)
    Subfactory.remove(self.parent, self)
end


function Floor.replace(self, dataset, object)
    object.parent = self
    return Collection.replace(self[dataset.class], dataset, object)
end

function Floor.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Floor.get_all(self, class)
    return Collection.get_all(self[class])
end

function Floor.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Floor.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Floor.shift(self, dataset, first_position, direction, spots)
    Collection.shift(self[dataset.class], dataset, first_position, direction, spots)
end

function Floor.count(self, class) return self[class].count end


-- Returns the machines and modules needed to actually build this floor
function Floor.get_component_data(self, component_table)
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

    -- Doesn't count subfloors when looking at this specific floors. Maybe it should, which
    -- would mean the subfactory machine total is equal to the floor total of the top floor
    for _, line in pairs(Floor.get_in_order(self, "Line")) do
        if line.subfloor == nil then
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
        end
    end

    return components
end


function Floor.pack(self)
    return {
        Line = Collection.pack(self.Line, Line),
        level = self.level,
        class = self.class
    }
end

-- This unpack-function differs in that it gets called with the floor already existing
-- This function should thus unpack itself into that floor, instead of creating a new one
function Floor.unpack(packed_self, self)
    -- This can't use Collection.unpack for its lines because of its recursive nature
    -- The calling function also needs to update its Subfactory to include the new subfloor references
    for _, packed_line in pairs(packed_self.Line.objects) do
        Floor.add(self, Line.unpack(packed_line, packed_self.level))
    end
    -- return value is not needed here
end


-- Needs validation: Line
function Floor.validate(self)
    self.valid = Collection.validate_datasets(self.Line, Line)
    return self.valid
end

-- Needs repair: Line
function Floor.repair(self, player)
    -- Unrepairable lines get removed, so the subfactory will always be valid afterwards
    Collection.repair_datasets(self.Line, player, Line)
    self.valid = true

    -- Make this floor remove itself if it's empty after repairs
    if self.level > 1 and self.Line.count < 2 then Floor.reset(self) end
end

-- 'Class' representing a floor of a subfactory with individual assembly lines
Floor = {}

function Floor.init(creating_line)
    local floor = {
        level = 1,  -- top floor has a level of 1, it's initialized with Floor.init(nil)
        origin_line = nil,  -- set below
        Line = Collection.init("Line"),
        valid = true,
        class = "Floor"
    }

    -- Move given line, if it exists, to the subfloor, and create a new origin line
    if creating_line ~= nil then
        -- Subfloors have a level that is 1 higher than their creating_line's floor
        floor.level = creating_line.parent.level + 1
        floor.parent = creating_line.parent

        local origin_line = Line.init(nil)
        -- No need to set a machine in this case

        origin_line.subfloor = floor
        floor.origin_line = origin_line

        Floor.replace(creating_line.parent, creating_line, origin_line)
        Floor.add(floor, creating_line)
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

    -- If the first line of a subfloor is removed, the whole subfloor needs to go
    if dataset.class == "Line" and self.level > 1 and dataset.gui_position == 1 then
        Floor.remove(self.origin_line.parent, self.origin_line)
    end

    return Collection.remove(self[dataset.class], dataset)
end

-- Floor deletes itself if it consists of only its mandatory first line
function Floor.remove_if_empty(self)
    if self.level > 1 and self.Line.count == 1 then
        local origin_line = self.origin_line
        local first_line = self.Line.datasets[1]

        Floor.replace(origin_line.parent, origin_line, first_line)
        -- No need to remove eventual subfloors to the given floor,
        -- as there can't be any if the floor is empty
        Subfactory.remove(self.parent, self)
    end
end

function Floor.replace(self, dataset, object)
    object.parent = self
    return Collection.replace(self[dataset.class], dataset, object)
end

function Floor.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Floor.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Floor.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
end

function Floor.shift_to_end(self, dataset, direction)
    return Collection.shift_to_end(self[dataset.class], dataset, direction)
end


-- Returns the machines and modules needed to actually build this floor
function Floor.get_component_data(self, component_table)
    local components = component_table or {machines={}, modules={}}

    local function add_to_count(table, object)
        local entry = table[object.proto.name]
        if entry == nil then
            table[object.proto.name] = {
                proto = object.proto,
                amount = object.amount
            }
        else
            entry.amount = entry.amount + object.amount
        end
    end

    for _, line in pairs(Floor.get_in_order(self, "Line")) do
        -- Doesn't count subfloors when looking at this specific floors. Maybe it should, which
        -- would mean the subfactory machine total is equal to the floor total of the top floor
        if line.subfloor == nil then
            local machine = line.machine
            local ceil_machine_count = math.ceil(machine.count)

            -- Machines
            add_to_count(components.machines, {
                proto = machine.proto,
                amount = ceil_machine_count
            })

            -- Modules
            for _, module in pairs(Machine.get_in_order(machine, "Module")) do
                add_to_count(components.modules, {
                    proto = module.proto,
                    amount = ceil_machine_count * module.amount
                })
            end

            -- Beacons
            local beacon = line.beacon
            if beacon and beacon.total_amount then
                local ceil_total_amount = math.ceil(beacon.total_amount)

                add_to_count(components.machines, {
                    proto = beacon.proto,
                    amount = ceil_total_amount
                })

                add_to_count(components.modules, {
                    proto = beacon.module.proto,
                    amount = ceil_total_amount * beacon.module.amount
                })
            end
        end
    end

    return components
end


function Floor.pack(self)
    return {
        Line = Collection.pack(self.Line),
        level = self.level,
        class = self.class
    }
end

-- This unpack-function differs in that it gets called with the floor already existing
-- This function should thus unpack itself into that floor, instead of creating a new one
function Floor.unpack(packed_self, self)
    -- This can't use Collection.unpack for its lines because of its recursive nature
    -- It might also be possible and more correct to move some of this functionality
    -- to the Line-class, but this works and is more understandable

    for _, packed_line in pairs(packed_self.Line.objects) do
        if packed_line.subfloor ~= nil then
            -- Add the first subfloor line as a line in this floor
            local subfloor_line = Line.unpack(packed_line.subfloor.Line.objects[1])
            Floor.add(self, subfloor_line)

            -- Use that line to create the subfloor, which moves it to the newly created floor
            local subfloor = Floor.init(subfloor_line)
            subfloor.origin_line.comment = packed_line.comment  -- carry over the origin_line's comment
            Subfactory.add(self.parent, subfloor)

            -- Remove the first subfloor line as it has already been created by initializing the subfloor with it
            table.remove(packed_line.subfloor.Line.objects, 1)

            Floor.unpack(packed_line.subfloor, subfloor)

        else  -- a normal line just gets unpacked and added straight away
            Floor.add(self, Line.unpack(packed_line))
        end
    end

    -- return value is not needed here
end


-- Needs validation: Line
function Floor.validate(self)
    self.valid = Collection.validate_datasets(self.Line)
    return self.valid
end

-- Needs repair: Line
function Floor.repair(self, player)
    -- Unrepairable lines get removed, so the subfactory will always be valid afterwards
    Collection.repair_datasets(self.Line, player)
    self.valid = true

    -- Make this floor remove itself if it's empty after repairs
    Floor.remove_if_empty(self)

    return true  -- make sure this floor is not removed by the calling Collection-function
end
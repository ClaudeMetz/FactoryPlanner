-- 'Class' representing a floor of a subfactory with individual assembly lines
Floor = {}

function Floor.init(line)
    local floor = {
        level = nil,
        origin_line = line,
        Line = Collection.init(),
        valid = true,
        class = "Floor"
    }

    -- Level becomes one more than the parent, or 1 if it's the top floor
    -- The top floor is initialised with Floor.init(nil)
    floor.level = line and (line.parent.level + 1) or 1

    -- If a line is given, add it as the first line of the new floor
    -- (This means that this floor is the subfloor of the given line)
    if line ~= nil then
        local subline = data_util.deepcopy(line)
        subline.comment = nil
        Floor.add(floor, subline)
    end

    return floor
end

function Floor.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Floor.remove(self, dataset)
    -- Remove the subfloor(s) associated to a line, if present
    if dataset.class == "Line" and dataset.subfloor ~= nil then
        Subfactory.remove(self.parent, dataset.subfloor)
    end

    return Collection.remove(self[dataset.class], dataset)
end

-- This leaves the object in disrepair, but it will be deleted anyway
function Floor.remove_subfloors(self)
    for _, line in pairs(self.Line.datasets) do
        if line.subfloor ~= nil then
            Subfactory.remove(self.parent, line.subfloor)
        end
    end
end

-- Floor deletes itself if it only has it's mandatory first line
function Floor.delete_empty(self)
    if self.level > 1 and self.Line.count == 1 then
        self.origin_line.subfloor = nil
        Subfactory.remove(self.parent, self)
    end
end

function Floor.replace(self, dataset, object)
    return Collection.replace(self[dataset.class], dataset, object)
end

function Floor.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Floor.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Floor.shift(self, dataset, direction)
    Collection.shift(self[dataset.class], dataset, direction)
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
        if component_table ~= nil and line.subfloor ~= nil then
            --[[ continue ]]
            
        else
            local ceil_machine_count = math.ceil(line.machine.count)

            -- Machines
            add_to_count(components.machines, {
                proto = line.machine.proto,
                amount = ceil_machine_count
            })

            -- Modules
            for _, module in pairs(Line.get_in_order(line, "Module")) do
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


-- Update validity of this floor and its subfloors
function Floor.update_validity(self)
    local classes = {Line = "Line"}
    self.valid = data_util.run_validation_updates(self, classes)
    if self.origin_line ~= nil then self.origin_line.valid = self.valid end
    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
function Floor.attempt_repair(self, player)
    self.valid = true
    
    local classes = {Line = "Line"}
    data_util.run_invalid_dataset_repair(player, self, classes)

    -- Remove floor if there are no recipes except the top one left
    if self.level > 1 and self.Line.count <= 1 then
        self.valid = false
    end

    return self.valid  -- Note success here so Line can remove subfloors if it was unsuccessful
end
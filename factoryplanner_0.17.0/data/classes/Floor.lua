require("util")

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

    if line ~= nil then
        Floor.add(floor, util.table.deepcopy(line))
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

    Collection.remove(self[dataset.class], dataset)
end

-- This leaves the object in disrepair, but it will be deleted anyway
function Floor.remove_subfloors(self)
    for _, line in pairs(self.Line.datasets) do
        if line.subfloor ~= nil then
            Subfactory.remove(self.parent, line.subfloor)
        end
    end
end

function Floor.replace(self, dataset, object)
    return Collection.replace(self[dataset.class], dataset, object)
end

function Floor.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Floor.get_in_order(self, class)
    return Collection.get_in_order(self[class])
end

function Floor.shift(self, dataset, direction)
    Collection.shift(self[dataset.class], dataset, direction)
end

-- Update validity of this floor and its subfloors
function Floor.update_validity(self, player)
    self.valid = true

    local classes = {"Line"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not _G[class].update_validity(dataset, player) then
                self.valid = false
            end
        end
    end

    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
function Floor.attempt_repair(self, player)
    self.valid = true
    
    local classes = {"Line"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not dataset.valid and not _G[class].attempt_repair(dataset, player) then
                Floor.remove(self, dataset)
            end
        end
    end

    -- Remove floor if there are no recipes except the top one left
    if self.level > 1 and self.Line.count == 1 then
        self.valid = false
    end

    return self.valid
end
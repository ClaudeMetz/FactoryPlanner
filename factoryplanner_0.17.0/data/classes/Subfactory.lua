-- 'Class' representing a independent part of the factory with in- and outputs
Subfactory = {}

function Subfactory.init(name, icon)
    local subfactory = {
        name = name,
        icon = nil,
        timescale = 60,
        energy_consumption = 0,
        notes = "",
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        Floor = Collection.init(),
        selected_floor = nil,
        valid = true,
        class = "Subfactory"
    }

    Subfactory.set_icon(subfactory, icon)

    -- Add first floor to the subfactory
    subfactory.selected_floor = Floor.init(nil)
    Subfactory.add(subfactory, subfactory.selected_floor)

    return subfactory
end

function Subfactory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Subfactory.remove(self, dataset)
    -- Removes all subfloors of a Floor to avoid orphanism
    if dataset.class == "Floor" then
        Floor.remove_subfloors(dataset)
    end

    Collection.remove(self[dataset.class], dataset)
end

function Subfactory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Subfactory.get_in_order(self, class)
    return Collection.get_in_order(self[class])
end

function Subfactory.get_by_name(self, class, name)
    return Collection.get_by_name(self[class], name)
end

function Subfactory.shift(self, dataset, direction)
    Collection.shift(self[dataset.class], dataset, direction)
end

-- Updates the validity of the whole subfactory
-- Floors can be checked in any order and separately without problem
function Subfactory.update_validity(self)
    self.valid = true
    
    local classes = {"Product", "Byproduct", "Ingredient", "Floor"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not _G[class].update_validity(dataset) then
                self.valid = false
            end
        end
    end

    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
-- (In general, Subfactory Items are not repairable and can only be deleted)
function Subfactory.attempt_repair(self, player)
    local classes = {"Product", "Byproduct", "Ingredient"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not dataset.valid then
                Subfactory.remove(self, dataset)
            end
        end
    end

    -- Floor repair is called on the top floor, which recursively goes through its subfloors
    -- Return value is not caught here because the top level floor won't be removed
    Floor.attempt_repair(Subfactory.get(self, "Floor", 1), player)

    self.valid = true
end

-- Exceptionally, a setter method to centralize edge-case handling
function Subfactory.set_icon(subfactory, icon)
    if icon ~= nil and icon.type == "virtual" then icon.type = "virtual-signal" end
    subfactory.icon = icon
end
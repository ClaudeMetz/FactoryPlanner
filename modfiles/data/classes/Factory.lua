---@class FPFactory
---@field Subfactory FPCollection<FPSubfactory>
---@field selected_subfactory FPSubfactory?
---@field export_modset ModToVersion
---@field class "Factory"

-- 'Class' representing the whole of a players actual data, including all subfactories
Factory = {}

---@return FPFactory
function Factory.init()
    return {
        Subfactory = Collection.init(),
        selected_subfactory = nil,
        -- A Factory can not become invalid
        class = "Factory"
    }
end

function Factory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Factory.insert_at(self, gui_position, object)
    object.parent = self
    return Collection.insert_at(self[object.class], gui_position, object)
end


function Factory.remove(self, dataset)
    local removed = Collection.remove(self[dataset.class], dataset)
    if self.selected_subfactory and self.selected_subfactory.id == dataset.id then
        self.selected_subfactory = self.Subfactory.datasets[1]  -- can be nil
    end
    return removed
end

---@return FPSubfactory
function Factory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

---@return FPSubfactory[]
function Factory.get_all(self, class)
    return Collection.get_all(self[class])
end

---@return FPSubfactory[]
function Factory.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Factory.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Factory.shift(self, dataset, first_position, direction, spots)
    Collection.shift(self[dataset.class], dataset, first_position, direction, spots)
end

function Factory.count(self, class) return self[class].count end

-- Imports every subfactory in the given string to this Factory, returning a reference to the first one
function Factory.import_by_string(self, export_string)
    local import_factory = util.porter.process_export_string(export_string)  ---@cast import_factory -nil
    -- No error handling here, as the export_string for this will always be known to work

    local first_subfactory = nil
    for _, subfactory in pairs(Factory.get_in_order(import_factory, "Subfactory")) do
        Factory.add(self, subfactory)
        first_subfactory = first_subfactory or subfactory
    end

    return first_subfactory
end


-- Updates every top level product of this Factory to the given product definition type
function Factory.update_product_definitions(self, new_defined_by)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        Subfactory.update_product_definitions(subfactory, new_defined_by)
    end
end

-- Updates the ingredient satisfaction data on every subfactory
function Factory.update_ingredient_satisfactions(self)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        solver.determine_ingredient_satisfaction(subfactory)
    end
end

function Factory.update_calculations(self, player)
    for _, subfactory in ipairs(Factory.get_in_order(self, "Subfactory")) do
        solver.update(player, subfactory)
    end
end

-- Needs validation: Subfactory
function Factory.validate(self)
    Collection.validate_datasets(self.Subfactory, Subfactory)
    -- Factories can't be invalid, this is just to cleanly validate the subfactories
end

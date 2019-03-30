-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(base_recipe, machine)
    local line = {
        recipe_name = base_recipe.name,
        recipe_category = base_recipe.category,
        recipe_energy = base_recipe.energy,
        percentage = 100,
        machine_name = machine.name,
        machine_count = 0,
        energy_consumption = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        subfloor = nil,
        valid = true,
        class = "Line"
    }

    for _, product in pairs(base_recipe.products) do
        Line.add(line, Item.init(product, "Product"))
    end
    for _, ingredient in pairs(base_recipe.ingredients) do
        Line.add(line, Item.init(ingredient, "Ingredient"))
    end

    return line
end

function Line.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Line.remove(self, dataset)
    Collection.remove(self[dataset.class], dataset)
end

function Line.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Line.get_in_order(self, class)
    return Collection.get_in_order(self[class])
end

function Line.shift(self, dataset, direction)
    Collection.shift(self[dataset.class], dataset, direction)
end

-- Update the validity of associated Items, recipe and machine of this line
function Line.update_validity(self)
    self.valid = true
    
    -- Validate Items
    local classes = {"Product", "Byproduct", "Ingredient"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not _G[class].update_validity(dataset) then
                self.valid = false
            end
        end
    end

    -- Validate the recipe and machine
    local recipe = global.all_recipes[self.recipe_name]
    if recipe == nil then
        self.valid = false
    else
        if recipe.category ~= self.recipe_category then
            self.valid = false
        else
            local machine = global.all_machines[self.recipe_category].machines[self.machine_name]
            if machine == nil then self.valid = false end
        end
    end

    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
-- (In general, Line Items are not repairable and can only be deleted)
function Line.attempt_repair(self, player)
    self.valid = true

    -- Remove invalid Items
    local classes = {"Product", "Byproduct", "Ingredient"}
    for _, class in pairs(classes) do
        for _, dataset in pairs(self[class].datasets) do
            if not dataset.valid then
                Subfactory.remove(self, dataset)
            end
        end
    end

    -- Attempt to repair the line
    local recipe = global.all_recipes[self.recipe_name]
    if recipe == nil then
        self.valid = false
    else
        if self.subfloor then
            -- Attempt to repair the subfloor, if this fails, remove it
            if not self.subfloor.valid and not Floor.attempt_repair(self.subfloor, player) then
                Subfactory.remove(self.subfloor.subfactory, self.subfloor)
                self.valid = false
            end
        else
            -- Attempt to repair an invalid machine
            -- (This is only done when there is no subfloor because it would become too complicated otherwise)
            if recipe.category ~= self.recipe_category then
                local machine = data_util.machines.get_default(player, recipe.category)
                Floor.replace(self.parent, self, Line.init(recipe, machine))
            else
                local machine = global.all_machines[self.recipe_category].machines[self.machine_name]
                if machine == nil then
                    self.machine_name = data_util.machines.get_default(player, recipe.category).name
                end
            end
        end
    end

    return self.valid
end
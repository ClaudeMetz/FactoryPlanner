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
        production_ratio = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        subfloor = nil,
        valid = true,
        class = "Line"
    }

    for _, product in pairs(base_recipe.products) do
        Line.add(line, Item.init(product, nil, "Product", 0))
    end
    for _, ingredient in pairs(base_recipe.ingredients) do
        Line.add(line, Item.init(ingredient, nil, "Ingredient", 0))
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
function Line.update_validity(self, player)
    -- Validate Items
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item"}
    self.valid = data_util.run_validation_updates(player, self, classes)

    -- Validate the recipe and machine
    local recipe = global.all_recipes[player.force.name][self.recipe_name]
    if recipe == nil then
        self.valid = false
    else
        self.recipe_energy = recipe.energy  -- update energy in case it changed
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
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item"}
    data_util.run_invalid_dataset_removal(player, self, classes, false)

    -- Attempt to repair the line
    local recipe = global.all_recipes[player.force.name][self.recipe_name]
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
            -- Repair an invalid machine (Only when there is no subfloor for simplicity)
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
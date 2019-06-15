-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(player, base_recipe, machine)
    local line = {
        recipe_name = base_recipe.name,
        recipe_energy = base_recipe.energy,
        percentage = 100,
        category_id = nil,
        machine_id = nil,
        machine_count = 0,
        energy_consumption = 0,
        fuel_id = nil,  -- gets set on first use, then stays set
        production_ratio = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        subfloor = nil,
        valid = true,
        class = "Line"
    }
    
    if machine ~= nil then  -- If given a machine, it gets used
        line.category_id = machine.category_id
        data_util.machines.change_machine(player, line, machine.id, nil)
    else  -- Otherwise, it takes the default machine for the given recipe
        line.category_id = global.all_machines.map[base_recipe.category]
        data_util.machines.change_machine(player, line, nil, nil)
    end

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
        -- When not category_id or machine_id are not set, a migration made them invalid
        if self.category_id == nil or self.machine_id == nil or self.fuel_id == nil then
            self.valid = false
        -- The ingredient_limit of the machine might have changed, reset the machine in that case
        elseif not data_util.machines.is_applicable(player, self.category_id, self.machine_id, self.recipe_name) then
            self.machine_id = nil
            self.valid = false
        end

        self.recipe_energy = recipe.energy  -- update energy in case it changed
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
        -- Attempt to repair the subfloor, if this fails, remove it
        if self.subfloor and not self.subfloor.valid and not Floor.attempt_repair(self.subfloor, player) then
            Subfactory.remove(self.subfloor.parent, self.subfloor)
            self.valid = false

        else
            -- Repair an invalid machine
            if self.category_id == nil then  -- Replace line with a new one (which includes a valid category)
                Floor.replace(self.parent, self, Line.init(player, recipe))
            elseif self.machine_id == nil then  -- Set the machine to the default one
                data_util.machines.change_machine(player, self, nil, nil)
            end

            if self.fuel_id == nil then  -- tries to use coal, uses the first one otherwise
                self.fuel_id = data_util.base_data.preferred_fuel()
            end
        end
    end

    return self.valid
end
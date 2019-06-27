-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(player, recipe, machine)
    local line = {
        recipe = recipe,
        machine = nil,
        percentage = 100,
        production_ratio = 0,
        energy_consumption = 0,
        fuel = nil,  -- gets set on first use, then stays set
        comment = nil,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        subfloor = nil,
        valid = true,
        class = "Line"
    }
    
    -- If machine is specified, it gets used, otherwise it'll fall back to the default
    if machine == nil then
        -- Hack together a pseudo-category for machine.change to use to find the default
        line.machine = {category = { id = global.all_machines.map[recipe.proto.category] } }
    end
    data_util.machine.change(player, line, machine, nil)

    for _, product in pairs(recipe.proto.products) do
        Line.add(line, Item.init_by_item(product, "Product", 0))
    end

    for _, ingredient in pairs(recipe.proto.ingredients) do
        Line.add(line, Item.init_by_item(ingredient, "Ingredient", 0))
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

-- Update the validity of values associated tp this line
function Line.update_validity(self)
    self.valid = true
    
    -- Validate Recipe
    if not Recipe.update_validity(self.recipe) then
        self.valid = false
    end

    -- Validate Items
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item"}
    if not data_util.run_validation_updates(self, classes) then
        self.valid = false
    end

    -- Validate Machine
    if not Machine.update_validity(self.machine) then
        self.valid = false
    -- If the machine is valid, it might still not be applicable
    elseif self.recipe.valid and not data_util.machine.is_applicable(self.machine, self.recipe) then
        self.valid = false
    end

    -- Validate Fuel
    if self.fuel ~= nil then
        local fuel_name = (type(self.fuel) == "string") and self.fuel or self.fuel.name
        local new_fuel_id = new.all_fuels.map[fuel_name]

        if new_fuel_id ~= nil then
            self.fuel = new.all_fuels.fuels[new_fuel_id]
        else
            self.fuel = self.fuel.name
            self.valid = false
        end
    end

    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
-- (In general, Line Items are not repairable and can only be deleted)
function Line.attempt_repair(self, player)
    self.valid = true
    
    -- Repair Recipe
    if not self.recipe.valid and not Recipe.attempt_repair(self.recipe) then
        self.valid = false
    end

    -- Repair Items
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item"}
    data_util.run_invalid_dataset_repair(player, self, classes)

    -- Repair Machine
    if self.valid and not self.machine.valid and not Machine.attempt_repair(self.machine) then
        if self.machine.category == nil then  -- No category means that it could not be repaired
            if self.valid then  -- If the line is still valid here, it has a valid recipe
                -- Replace this line with a new one (with a new category)
                Floor.replace(self.parent, self, Line.init(player, self.recipe, nil))
            end
        else
            -- Set the machine to the default one
            data_util.machine.change(player, self, nil, nil)
        end
    end

    -- Repair Fuel
    if self.valid and self.fuel ~= nil and type(self.fuel) == "string" then
        local current_fuel_id = global.all_fuels.map[self.fuel]
        if current_fuel_id ~= nil then
            self.fuel = global.all_fuels.fuels[current_fuel_id]
        else
            -- If it is not found, set it to the default
            self.fuel = data_util.base_data.preferred_fuel(global)
        end
    end

    -- Repair subfloor (continues through recursively)
    if self.subfloor and not self.subfloor.valid and not Floor.attempt_repair(self.subfloor, player) then
        Subfactory.remove(self.subfloor.parent, self.subfloor)
    end

    return self.valid
end
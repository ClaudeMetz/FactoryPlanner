-- This file contains all code relating to calculating the production values for a subfactory
-- Also, this code sucks and I hate it (this code has become really awful)
calc = {
    aggregate = {}
}

-- Updates the whole subfactory calculations from top to bottom
function calc.update(player, subfactory)
    -- Get products that need to be produced
    local required_products = calc.aggregate.init()
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local aggregate_item = calc.aggregate.item_init(product, "Product", product.required_amount)
        aggregate_item.main = true
        calc.aggregate.add(required_products, aggregate_item)
    end
    
    -- Begin calculation on the top floor, which recursively goes through its subfloors
    local floor = Subfactory.get(subfactory, "Floor", 1)  -- top floor
    local result = calc.update_floor(player, subfactory, floor, required_products)

    -- Update top level items to the new calculations
    calc.update_subfactory(subfactory, result)
end


-- Updates the given floor, including subfloors (is always called for floor.level = 1, the parameter is for recursion)
-- Gets passed a partially filled aggregate containing the main products for this floor
function calc.update_floor(player, subfactory, floor, aggregate)
    for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
        -- If a line has a subfloor, it is calculated first, to then adjust the line itself with the subfloor result
        if line.subfloor ~= nil then
            local subfloor_aggregate = calc.aggregate.init_with_recipe(aggregate, line.recipe, true, true)
            local subfloor_result = calc.update_floor(player, subfactory, line.subfloor, subfloor_aggregate)
            calc.update_line(line, subfloor_result)

        -- Otherwise, calculate the line by itself and adjust it accordingly
        else
            -- Some local functions to avoid too many parameters needing to be passed
            local function calculate_production_ratio(item)
                local product = calc.aggregate.get(aggregate, "Product", item)
                if item.net then
                    if item.net > 0 then return (math.abs(product.amount) * (line.percentage / 100)) / item.net
                    else return 0 end
                else
                    return (math.abs(product.amount) * (line.percentage / 100)) / item.ratio
                end
            end

            local function calculate_produced_amount(item, production_ratio)
                return (item.ratio * production_ratio)
            end

            local line_aggregate, item_count = calc.aggregate.init_with_recipe(aggregate, line.recipe, false, false)
            
            local production_ratio = 0
            if item_count == 0 then
                -- recipe is useless, do nothing
            elseif item_count == 1 then
                production_ratio = calculate_production_ratio(calc.aggregate.get_in_order(line_aggregate, "Product")[1])
            else  -- 2+ relevant Products
                -- Determine the highest production ratio needed to fulfill demand
                for _, product in pairs(calc.aggregate.get_in_order(line_aggregate, "Product")) do
                    local ratio = calculate_production_ratio(product)
                    production_ratio = math.max(production_ratio, ratio)
                end
            end

            -- Set production ratio to calculate machine_counts for all available machines when needed
            line_aggregate.production_ratio = production_ratio

            -- If the recipe is not useless, calculate all remaining item amounts
            if production_ratio > 0 then
                -- Byproducts
                for _, byproduct in pairs(calc.aggregate.get_in_order(line_aggregate, "Byproduct")) do
                    byproduct.amount = calculate_produced_amount(byproduct, production_ratio)
                end

                -- Products
                for _, product in pairs(calc.aggregate.get_in_order(line_aggregate, "Product")) do
                    product.amount = calculate_produced_amount(product, production_ratio)

                    -- Add overflow product (case of multiple relevant products) as byproducts
                    local aggregate_product = calc.aggregate.get(aggregate, "Product", product)
                    if product.amount > aggregate_product.amount then
                        local overflow_amount = product.amount - aggregate_product.amount
                        product.amount = aggregate_product.amount
                        calc.aggregate.add(line_aggregate, calc.aggregate.item_init(product, "Byproduct", overflow_amount))
                    end
                end
                
                -- Ingredients
                for _, ingredient in pairs(calc.aggregate.get_in_order(line_aggregate, "Ingredient")) do
                    ingredient.amount = calculate_produced_amount(ingredient, production_ratio)

                    local line_byproduct = calc.aggregate.get(line_aggregate, "Byproduct", ingredient)
                    if line_byproduct ~= nil then
                        if ingredient.amount == line_byproduct.amount then  -- remove both byproduct and ingredient
                            calc.aggregate.remove(line_aggregate, line_byproduct)
                            calc.aggregate.remove(line_aggregate, ingredient)

                        elseif ingredient.amount > line_byproduct.amount then  -- remove byproduct, reduce ingredient amount
                            calc.aggregate.remove(line_aggregate, line_byproduct)
                            ingredient.amount = ingredient.amount - line_byproduct.amount

                        elseif ingredient.amount < line_byproduct.amount then  -- reduce byproduct amount, remove ingredient
                            line_byproduct.amount = line_byproduct.amount - ingredient.amount
                            calc.aggregate.remove(line_aggregate, ingredient)
                        end
                    end
                end

                -- Machine count (Same calculation for machines and miners because the machine and line values are adjusted beforehand)
                line_aggregate.machine_count = (production_ratio / (line.machine.proto.speed / line.recipe.energy)) / subfactory.timescale

                -- Energy consumption
                local energy_consumption = line_aggregate.machine_count * (line.machine.proto.energy * 60)
                local burner = line.machine.proto.burner
                if burner == nil then
                    line_aggregate.energy_consumption = energy_consumption
                elseif burner.categories["chemical"] then
                    -- Only applies to lines without subfloor (lines with subfloor shouldn't have fuel)
                    line.fuel = line.fuel or get_preferences(player).preferred_fuel
                    local fuel_amount = ((energy_consumption / burner.effectivity) / line.fuel.fuel_value) * subfactory.timescale
                    
                    -- How this is added is silly and needs to be fixed with the future proper interface
                    local item = Item.init_by_proto(line.fuel, "Ingredient", fuel_amount)
                    item.fuel = true
                    calc.aggregate.add(line_aggregate, calc.aggregate.item_init(item, "Ingredient", fuel_amount))
                end

            else  -- Reset the product counts
                for _, product in pairs(calc.aggregate.get_in_order(line_aggregate, "Product")) do product.amount = 0 end
                --queue_message(player, {"label.hint_useless_recipe"}, "hint")
            end
            
            calc.update_line(line, line_aggregate)
        end

        calc.aggregate.incorporate_line(aggregate, line)
    end

    -- At the end, transform all outstanding (non-main) Products into Ingredients
    for _, product in pairs(calc.aggregate.get_in_order(aggregate, "Product")) do
        if not product.main then  -- main Products stay products to be transfered to a top-level Product
            calc.aggregate.add(aggregate, calc.aggregate.item_init(product, "Ingredient", product.amount))
            calc.aggregate.remove(aggregate, product)
        elseif floor.level > 1 then  -- the top floor does it's own processing related to the subfactory
            product.amount = product.required_amount - product.amount
        end
    end

    return aggregate
end

-- Updates the subfactory top-level items, conserving previous ordering
function calc.update_subfactory(subfactory, result)
    -- Energy consumption
    subfactory.energy_consumption = result.energy_consumption

    -- Products
    for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local result_product = calc.aggregate.get(result, "Product", product)

        if result_product == nil then product.amount = 0
        else product.amount = math.max(product.required_amount - result_product.amount, 0) end
    end
    
    calc.update_item_collection(subfactory, "Byproduct", result)
    calc.update_item_collection(subfactory, "Ingredient", result)
end

-- Updates a line with the results from its subfloor, conserving previous ordering
function calc.update_line(line, result)
    line.energy_consumption = result.energy_consumption
    line.machine.count = result.machine_count
    line.production_ratio = result.production_ratio

    classes = {"Product", "Byproduct", "Ingredient"}
    for _, class in pairs(classes) do
        calc.update_item_collection(line, class, result)
    end
end

-- Updates an item collection with new result data, conserving previous ordering
-- They can have both their amounts changed and be added/removed
function calc.update_item_collection(object, class, result)
    -- First, update/remove existing top level items
    for _, item in pairs(_G[object.class].get_in_order(object, class)) do
        local result_item = calc.aggregate.get(result, class, item)
        if result_item == nil or (object.class == "Subfactory" and result_item.amount == 0) then
            _G[object.class].remove(object, item)
        else
            item.amount = result_item.amount
            result_item.touched = true
        end
    end

    -- Then, add remaining result items as new top level items
    for _, result_item in pairs(calc.aggregate.get_in_order(result, class)) do
        if not result_item.touched then
            if not (object.class == "Subfactory" and result_item.amount == 0) then
                local item = nil
                if result_item.proto then
                    item = Item.init_by_proto(result_item.proto, class, result_item.amount)
                else
                    item = Item.init_by_item(result_item, class, result_item.amount)
                end
                item.fuel = result_item.fuel
                _G[object.class].add(object, item)
            end
        end
    end
end


-- Initialise an aggregate
function calc.aggregate.init()
    local aggregate = { 
        energy_consumption = 0,
        machine_count = 0
    }

    classes = {"Product", "Byproduct", "Ingredient"}
    for _, class in pairs(classes) do
        aggregate[class] = {}
        
        local types = {"item", "fluid", "entity"}
        for _, type in pairs(types) do
            aggregate[class][type] = Collection.init()
            aggregate[class][type].map = {}
        end
    end
    
    return aggregate
end

-- Creates an aggregate containing any relevant products (optionally with byproducts and ingredients)
function calc.aggregate.init_with_recipe(main_aggregate, recipe, products_only, main)
    local aggregate = calc.aggregate.init()
    local item_count = 0
    
    -- Products and Byproducts
    for _, product in pairs(recipe.proto.products) do
        local main_product = calc.aggregate.get(main_aggregate, "Product", product)
        if main_product ~= nil and main_product.type ~= "entity" then
            local aggregate_product = calc.aggregate.item_init(product, "Product", main_product.amount)
            if main then
                aggregate_product.main = true
                aggregate_product.required_amount = main_product.amount
            end

            item_count = item_count + 1
            calc.aggregate.add(aggregate, aggregate_product)
        elseif not products_only then
            --item_count = item_count + 1
            calc.aggregate.add(aggregate, calc.aggregate.item_init(product, "Byproduct", 0))
        end
    end
    
    -- Ingredients
    if not products_only then
        for _, ingredient in pairs(recipe.proto.ingredients) do
            -- Check for recipes with the same items as both ingredients and products
            local product = calc.aggregate.get(aggregate, "Product", ingredient)
            if product and ingredient.type ~= "entity" then product.net = product.ratio - ingredient.amount end
            --item_count = item_count + 1
            calc.aggregate.add(aggregate, calc.aggregate.item_init(ingredient, "Ingredient", 0))
        end
    end
    
    return aggregate, item_count
end

-- Creates a special item to be put in an aggregate
function calc.aggregate.item_init(base_item, class, amount)
    local item
    if base_item.proto then
        item = Item.init_by_proto(base_item.proto, class, amount)
    else
        item = Item.init_by_item(base_item, class, amount)
    end
    item.type = item.proto.type
    item.name = item.proto.name
    item.fuel = base_item.fuel

    if base_item.class then 
        item.ratio = base_item.ratio
    else
        -- (This function incidentally handles ingredients as well)
        item.ratio = data_util.determine_product_amount(base_item)
    end
    return item
end

-- Add an object to the aggregate, or adds it's amount to an already existing item (negative values subtract)
function calc.aggregate.add(aggregate, aggregate_object)
    local collection = aggregate[aggregate_object.class][aggregate_object.type]
    local aggregate_item = collection.datasets[collection.map[aggregate_object.name]]
    
    if aggregate_item ~= nil then
        aggregate_item.amount = aggregate_item.amount + aggregate_object.amount
        
        if not aggregate_item.main and aggregate_item.amount == 0 then
            calc.aggregate.remove(aggregate, aggregate_item)
        end
    else
        local aggregate_item = Collection.add(collection, aggregate_object)
        collection.map[aggregate_object.name] = aggregate_item.id
    end
end

-- Removes given item from the aggregate
function calc.aggregate.remove(aggregate, item)
    aggregate[item.class][item.type].map[item.name] = nil
    Collection.remove(aggregate[item.class][item.type], item)
end

-- Returns given item from the aggregate
function calc.aggregate.get(aggregate, class, object)
    local t, name = object.type, object.name
    if not object.type or type(object.type) == "table" then
        t, name = object.proto.type, object.proto.name
    end
    local collection = aggregate[class][t]
    return collection.datasets[collection.map[name]]
end

-- Returns items from all 3 types in one list
function calc.aggregate.get_in_order(aggregate, class)
    local collection = aggregate[class]
    local types = {"item", "fluid", "entity"}

    local ordered_list = {}
    for _, type in pairs(types) do
        for _, item in pairs(collection[type].datasets) do
            table.insert(ordered_list, item)
        end
    end

    return ordered_list
end


-- Incorporates given line into given aggregate
function calc.aggregate.incorporate_line(aggregate, line)
    aggregate.energy_consumption = aggregate.energy_consumption + line.energy_consumption
    if line.gui_position == 1 then 
        aggregate.machine_count = line.machine.count
        aggregate.production_ratio = line.production_ratio
    end

    for _, product in pairs(Line.get_in_order(line, "Product")) do
        calc.aggregate.add(aggregate, calc.aggregate.item_init(product, "Product", -product.amount))
    end

    for _, byproduct in pairs(Line.get_in_order(line, "Byproduct")) do
        calc.aggregate.add(aggregate, calc.aggregate.item_init(byproduct, "Byproduct", byproduct.amount))
    end

    -- Ingredients get added as Products, minus the Byproducts being used up
    for _, ingredient in pairs(Line.get_in_order(line, "Ingredient")) do
        calc.aggregate.balance_byproducts_and_ingredients(aggregate, ingredient)
    end
end

-- Subtracts existing byproducts from ingredients and other stuff, also great function name
function calc.aggregate.balance_byproducts_and_ingredients(aggregate, ingredient)
    local aggregate_byproduct = calc.aggregate.get(aggregate, "Byproduct", ingredient)
    if aggregate_byproduct ~= nil then
        if ingredient.amount == aggregate_byproduct.amount then  -- remove byproduct, don't add ingredient
            calc.aggregate.remove(aggregate, aggregate_byproduct)

        elseif ingredient.amount > aggregate_byproduct.amount then  -- remove byproduct, add less of the ingredient
            calc.aggregate.add(aggregate, calc.aggregate.item_init(ingredient, "Product",
                ingredient.amount - aggregate_byproduct.amount))
            calc.aggregate.remove(aggregate, aggregate_byproduct)

        elseif ingredient.amount < aggregate_byproduct.amount then  -- remove some of the byproduct, don't add ingredient
            aggregate_byproduct.amount = aggregate_byproduct.amount - ingredient.amount
        end
    else  -- add the ingredient in full
        calc.aggregate.add(aggregate, calc.aggregate.item_init(ingredient, "Product", ingredient.amount))
    end
end
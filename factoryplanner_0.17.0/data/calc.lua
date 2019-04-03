-- This file contains all code relating to calculating the production values for a subfactory
-- It could be written into the classes themselves, but outsourcing it here is more cogent

calc = {}

-- Updates the given floor, including subfloors (should always be called on floor 1, floor parameter is for recursion)
function calc.update_floor(player, subfactory_id, floor, required_products)
    local new_aggregate = Aggregate.init()
    new_aggregate.fresh = false
    local subfactory = Factory.get_subfactory(player, subfactory_id)

    -- If you are on the top floor, take the top level items as baseline products
    if floor.level == 1 then required_products = subfactory["Product"].datasets end
    -- If you are not, take the required products (passed by parameter) as your baseline products
    for _, product in pairs(required_products) do
        Aggregate.add_item(new_aggregate, "products", product, (-1 * product.amount_required), true)
    end

    for _, id in ipairs(data_util.order_by_position(floor.lines)) do
        local line = floor.lines[id]
        
        -- If (assembly) line is a subfloor, it recalculates itself first, then adds to the aggregate
        if line.type == "FloorReference" then
            -- First, search for relevant products that this subfloor produces
            local required_products = {}
            for _, product in pairs(global.all_recipes[player.force.name][line.recipe_name].products) do
                local aggregate_product = new_aggregate.products[product.name]
                if aggregate_product ~= nil and aggregate_product.item_type ~= "entity" then
                    product.amount_required = (-1 * aggregate_product.amount)
                    product.item_type = aggregate_product.item_type
                    table.insert(required_products, product)
                end
            end

            -- Then, recalculate it (recursively), incorporate newly calculated data, then continue to the next line
            local subfloor = Subfactory.get(player, subfactory_id, "Floor", line.floor_id)
            calc.update_floor(player, subfactory_id, subfloor, required_products)
            Aggregate.add_aggregate(new_aggregate, subfloor.aggregate, required_products)
            for _, product in pairs(required_products) do 
                Aggregate.add_item(subfloor.aggregate, "products", product, product.amount, false)
            end
            Floor.update_aggregate_line(player, subfactory_id, line.floor_id)
        else
            -- Some local functions to avoid too many parameters needing to be passed
            local function calculate_production_ratio(item)
                return (math.abs(new_aggregate[item.kind][item.name].amount) * (line.percentage / 100)) / item.ratio
            end

            local function calculate_produced_amount(item, production_ratio)
                return (item.ratio * production_ratio)
            end

            Line.reset(player, subfactory_id, floor.id, line.id)
            local relevant_products = {}
            -- First, go through all recipe products and find out which of them this line produces
            for product_id, product in pairs(line.products.datasets) do
                local aggregate_product = new_aggregate.products[product.name]
                if aggregate_product ~= nil and aggregate_product.item_type ~= "entity" then
                    table.insert(relevant_products, product)
                else  -- Meaning the product is a byproduct
                    product.kind = "byproducts"  -- aggregate is updated after actual calculations
                end
            end
            
            local defining_product
            local production_ratio = 0
            if #relevant_products == 0 then  
                -- amount produced stays at 0, recipe is useless, byproducts moved to products for aesthetic purposes
                Line.reset(player, subfactory_id, floor.id, line.id)

            elseif #relevant_products == 1 then
                defining_product = relevant_products[1]
                production_ratio = calculate_production_ratio(relevant_products[1])

            else --[[  -- 2+ relevant products
                -- First, find out which product amount needs the most iterations of the recipe to be satisfied (=defining)
                for _, product in ipairs(relevant_products) do
                    local amount_to_produce = new_aggregate.products[product.name].amount * (line.percentage / 100)
                    local new_prod_ratio = (amount_to_produce / product.ratio) 
                    if production_ratio < new_prod_ratio then 
                        production_ratio = new_prod_ratio
                        defining_product = product
                    end
                end
                
                -- Then, move overflow of other products to byproducts
                for _, product in ipairs(relevant_products) do
                    if defining_product.name ~= product.name then
                        local amount_to_produce = new_aggregate.products[product.name].amount * (line.percentage / 100)
                        local overflow_amount = (production_ratio * product.ratio) - amount_to_produce
                        product.amount = amount_to_produce

                        if overflow_amount > data_util.margin_of_error then
                            local byproduct_id = LineItem.add_to_list(line.products, LineItem.init(product, "byproducts"))
                            line.products.datasets[byproduct_id].amount = overflow_amount
                            line.products.datasets[byproduct_id].duplicate = true

                            Aggregate.add_item(new_aggregate, "byproducts", product, overflow_amount, false)
                            new_aggregate.products[product.name] = nil
                        end
                    end
                end ]]
            end
            
            -- If the recipe is not useless, calculate all remaining item amounts
            if defining_product then
                line.production_ratio = production_ratio  -- Used for calculating machine_counts for all available machines

                -- Products and Byproducts
                for _, product in pairs(line.products.datasets) do
                    product.amount = calculate_produced_amount(product, production_ratio)
                    Aggregate.add_item(new_aggregate, product.kind, product, product.amount, false)
                end

                -- Ingredients
                for _, ingredient in pairs(line.ingredients.datasets) do
                    ingredient.amount = calculate_produced_amount(ingredient, production_ratio)
                    Aggregate.add_ingredient_as_product(new_aggregate, ingredient)
                end

                -- Machines (Same for machines and miners because the machine and line values are adjusted beforehand)
                local machine = global.all_machines[line.recipe_category].machines[line.machine_name]
                line.machine_count = (production_ratio / (machine.speed / line.recipe_energy)) / subfactory.timescale

                -- Energy consumption
                if not machine.burner then
                    line.energy_consumption = line.machine_count * (machine.energy * 60)
                    new_aggregate.energy_consumption = new_aggregate.energy_consumption + line.energy_consumption
                end
            end
        end
    end

    -- At the end, transform all outstanding (non-top-level) products into ingredients
    for _, product in pairs(new_aggregate.products) do
        if not product.top_level then  -- top level products stay there to later be detected as not (wholly) produced
            Aggregate.add_item(new_aggregate, "ingredients", product, (-1 * product.amount), false)
            new_aggregate.products[product.name] = nil
        end
    end
    
    -- Replace the old aggregate
    floor.aggregate = new_aggregate
end
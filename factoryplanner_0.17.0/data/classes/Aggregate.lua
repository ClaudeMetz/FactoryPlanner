-- This is not really a class in the same sense as the others in this project,
-- but it serves to unify some common operations in a class-like fashion
-- (The whole class system is a mess and needs to be redone at some point)

Aggregate = {}

function Aggregate.init()
    return {
        energy_consumption = 0,
        products = {},
        byproducts = {},
        ingredients = {},
        fresh = true
    }
end

-- Either creates or adds to given item in given aggregate
function Aggregate.add_item(aggregate, category, item, amount, top_level)
    local items = aggregate[category]
    if math.abs(amount) > 0 then
        if items[item.name] == nil then
            local new_item = {
                name = item.name, 
                item_type = item.item_type,
                amount = amount,
                top_level = top_level  -- indicates whether a product is top-level
            }
            items[item.name] = new_item
        else
            items[item.name].amount = items[item.name].amount + amount
            -- Removes item if it's amount is below the margin of error
            if math.abs(items[item.name].amount) < data_util.margin_of_error then
                items[item.name] = nil
            end
        end
    end
end

-- Merges the second aggregate into the first one (ie. expanding the first one)
function Aggregate.add_aggregate(aggregate, second_aggregate, required_products)
    aggregate.energy_consumption = aggregate.energy_consumption + second_aggregate.energy_consumption

    -- Products are handled differently because of how the product aggregate works
    -- (0 of a main product means it is produced fully, this is detected here)
    for _, req_product in pairs(required_products) do
        local aggregate_product = second_aggregate[req_product.name]
        if not aggregate_product then  -- Product amount produced exactly
            req_product.amount = req_product.amount_required
        else  -- Product over- or under-produced
            req_product.amount = req_product.amount_required + aggregate_product.amount
        end
        Aggregate.add_item(aggregate, "products", req_product, req_product.amount, false)
    end

    -- Byproducts are added as normal
    for _, byproduct in pairs(second_aggregate.byproducts) do
        Aggregate.add_item(aggregate, "byproducts", byproduct, byproduct.amount, false)
    end

    -- Ingredients are added as products for the further calculus
    for _, ingredient in pairs(second_aggregate.ingredients) do
        Aggregate.add_ingredient_as_product(aggregate, ingredient)
    end
end

-- Adds a line ingredient as a product to produce, using up existing byproducts first
function Aggregate.add_ingredient_as_product(aggregate, ingredient)
    if aggregate.byproducts[ingredient.name] ~= nil then
        local byproduct = aggregate.byproducts[ingredient.name]
        if byproduct.amount >= ingredient.amount then
            byproduct.amount = byproduct.amount - ingredient.amount
        else  -- byproduct.amount < ingredient.amount
            ingredient.amount = ingredient.amount - byproduct.amount
            byproduct.amount = 0
        end
    end
    Aggregate.add_item(aggregate, "products", ingredient, (-1 * ingredient.amount), false)
end
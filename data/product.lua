-- Adds a product to the specified subfactory
function add_product(id, name, amount_required)
    local products = global["subfactories"][id]["products"]
    local product = 
    {
        name = name,
        amount_required = amount_required,
        amount_produced = 0,
        gui_position = #products+1
    }
    table.insert(products, product)
    local id = #products
    return id
end

-- Deletes a product from the database
function delete_product(id, product_id)
    table.remove(global["subfactories"][id]["products"], product_id)
end

-- Returns the products attached to the given subfactory
function get_products(id)
    return global["subfactories"][id].products
end

-- Returns the specified product attached to the given subfactory
-- If it is not found, an uninitialised product table is returned
function get_product(id, product_id)
    if product_id ~= 0 then
        return global["subfactories"][id]["products"][product_id]
    else 
        return {name=nil, amount_required=""}
    end
end

-- Returns true when a product already exists in given subfactory
function product_exists(id, product_name)
    for _, product in ipairs(global["subfactories"][id]["products"]) do
        if product.name == product_name then return true end
    end
    return false
end


-- Changes the amount produced of given product by given amount
function change_product_amount_produced(id, product_id, amount)
    global["subfactories"][id]["products"][product_id].amount_produced = 
      global["subfactories"][id]["products"][product_id].amount_produced + amount
end

-- Sets the amount required of given product to given amount
function set_product_amount_required(id, product_id, amount)
    global["subfactories"][id]["products"][product_id].amount_required = amount     
end


-- Checks subfactory products for validity, optionally deletes all invalid ones
function check_product_validity(items, fluids, subfactory_id, delete)
    local validity = true
    for id, product in ipairs(get_products(subfactory_id)) do
        if not (items[product.name] or fluids[product.name]) then
            validity = false
            if delete then
                delete_product(subfactory_id, id)
            else break end
        end
    end
    return validity
end
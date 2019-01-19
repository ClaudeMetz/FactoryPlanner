-- Adds a new subfactory to the database
function add_subfactory(name, icon)
    local subfactory = 
    {
        name = name,
        icon = icon,
        timescale = 60,
        gui_position = #global["subfactories"]+1,
        products = {},
        byproducts = {},
        ingredients = {}
    }
    table.insert(global["subfactories"], subfactory)
    local id = #global["subfactories"]
    return id
end

-- Changes subfactory name and icon
function edit_subfactory(id, name, icon)
    global["subfactories"][id].name = name
    global["subfactories"][id].icon = icon
end

-- Deletes a subfactory from the database
function delete_subfactory(id)
    table.remove(global["subfactories"], id)

    -- Moves the selected subfactory down by 1 if it's the last in the list being deleted
    if global["subfactories"][id] == nil then
        global["selected_subfactory_id"] = #global["subfactories"]
    end
end


-- Returns the gui position of the given subfactory
function get_subfactory_gui_position(id)
    return global["subfactories"][id].gui_position
end

-- Swaps the position of the given subfactories
function swap_subfactory_positions(id1, id2)
    local subfactories = global["subfactories"]
    subfactories[id1].gui_position, subfactories[id2].gui_position = 
      subfactories[id2].gui_position, subfactories[id1].gui_position
end


-- Returns the list containing all subfactories
function get_subfactories()
    return global["subfactories"]
end

-- Returns the subfactory specified by the id
function get_subfactory(id)
    return global["subfactories"][id]
end

-- Returns the total number of subfactories
function get_subfactory_count()
    return #global["subfactories"]
end


-- Returns the current timescale of the given subfactory
function get_subfactory_timescale(id)
    return global["subfactories"][id].timescale
end

function set_subfactory_timescale(id, timescale)
    global["subfactories"][id].timescale = timescale
end


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
function get_product(id, product_id)
    return global["subfactories"][id]["products"][product_id]
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
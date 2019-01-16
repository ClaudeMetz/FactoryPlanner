-- Adds a new subfactory to the database
function add_subfactory(name, icon)
    local subfactory = 
    {
        name = name,
        icon = icon,
        products = {},
        byproducts = {},
        ingredients = {}
    }
    table.insert(global["subfactories"], subfactory)
    local id = get_subfactory_count()
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
    if get_subfactory(id) == nil then
        global["selected_subfactory_id"] = get_subfactory_count()
    end
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

-- Moves given subfactory to either right or left by 1 position
function move_subfactory(id, direction)
    local subfactories = global["subfactories"]
    if direction == "right" then
        subfactories[id], subfactories[id+1] = subfactories[id+1], subfactories[id]
    else
        subfactories[id], subfactories[id-1] = subfactories[id-1], subfactories[id]
    end
end

function get_products(id)
    return global["subfactories"][id].products
end
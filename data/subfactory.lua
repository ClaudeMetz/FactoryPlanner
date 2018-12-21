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
    local subfactories = global["subfactories"]
    if subfactories[id] == nil then
        global["selected_subfactory_id"] = #subfactories
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
-- Adds a new subfactory to the databaae and returns it's id
function add_subfactory(name, icon)
    table.insert(global["subfactories"], {name = name, icon = icon})

    -- Sets the currently selected subfactory to the new one
    global["selected_subfactory_id"] = #global["subfactories"]
end

-- Changes a subfactory from the database
function edit_subfactory(id, name, icon)
    global["subfactories"][id].name= name
    global["subfactories"][id].icon = icon
end

-- Deletes a sunfactory from the database
function delete_subfactory(id)
    table.remove(global["subfactories"], id)

    -- Moves the selected subfactory down by 1 if the last in the list is deleted
    local subfactories = global["subfactories"]
    if subfactories[id] == nil then
        global["selected_subfactory_id"] = #subfactories
    end
end
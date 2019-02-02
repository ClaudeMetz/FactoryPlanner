-- Adds a new subfactory to the database
function add_subfactory(name, icon)
    local subfactory = 
    {
        name = name,
        icon = icon,
        timescale = 60,
        notes = "",
        valid = true,
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


-- Returns the current timescale of the given subfactory
function get_subfactory_timescale(id)
    return global["subfactories"][id].timescale
end

-- Sets the timescale of the given subfactory
function set_subfactory_timescale(id, timescale)
    global["subfactories"][id].timescale = timescale
end


-- Returns the notes string of the given subfactory
function get_subfactory_notes(id)
    return global["subfactories"][id].notes
end

-- Sets the notes of the given subfactory
function set_subfactory_notes(id, notes)
    global["subfactories"][id].notes = notes
end


-- Returns whether the given subfactory is valid (= contains valid items+recipes)
function is_subfactory_valid(id) 
    return global["subfactories"][id].valid
end

-- Sets the validity of the given subfactory
function set_subfactory_validity(id, validity)
    global["subfactories"][id].valid = validity
end

-- Returns array of validation functions for each relevant part of a subfactory 
function get_validation_functions()
    return {check_product_validity}
end

-- Checks all subfactories for missing items and recipes and sets their respective flags
function determine_subfactory_validity()
    local items = game.item_prototypes
    local fluids = game.fluid_prototypes

    for id, _ in ipairs(global["subfactories"]) do
        local validity = true
        for _, f in pairs(get_validation_functions()) do
            if not f(items, fluids, id, false) then
                validity = false
                break
            end
        end
        set_subfactory_validity(id, validity)
    end
end

-- Deletes all invalid items/recipes from the given subfactory
function delete_invalid_subfactory_parts(subfactory_id)
    local items = game.item_prototypes
    local fluids = game.fluid_prototypes

    for _, f in pairs(get_validation_functions()) do
        f(items, fluids, subfactory_id, true)
    end
    set_subfactory_validity(subfactory_id, true)
end
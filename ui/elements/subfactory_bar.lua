-- Creates the subfactory bar that includes all current subfactory buttons
function add_subfactory_bar_to(main_dialog, player)
    local subfactory_bar = main_dialog.add{type="scroll-pane", name="scroll-pane_subfactory_bar", direction="vertical"}
    subfactory_bar.style.maximal_height = 84
    subfactory_bar.style.bottom_padding = 6

    local table_subfactories = subfactory_bar.add{type="table", name="table_subfactories", column_count = 1}
    table_subfactories.style.vertical_spacing = 4

    refresh_subfactory_bar(player)
end


-- Refreshes the subfactory bar by reloading the data
function refresh_subfactory_bar(player)
    local table_subfactories =  player.gui.center["fp_main_dialog"]["scroll-pane_subfactory_bar"]["table_subfactories"]
    table_subfactories.clear()

    local max_width = global["main_dialog_dimensions"].width * 0.9
    local width_remaining = 0
    local current_table_index = 0
    local current_table = nil

    -- selected_subfactory_id is 0 when there are no subfactories
    if global["selected_subfactory_id"] ~= 0 then
        for _, id in ipairs(global["subfactory_order"]) do
            local subfactory = get_subfactory(id)
            local selected = (global["selected_subfactory_id"] == id)
            
            -- Tries to insert new element, if it doesn't fit, a new row is created and creation is reattempted
            -- First one is supposed to fail to create the first table
            local width_used = attempt_element_creation(current_table, width_remaining, id, subfactory, selected)
            if width_used == 0 then
                current_table = table_subfactories.add{type="table", name="table_subfactories_" .. current_table_index, 
                  column_count = 30}
                current_table_index = current_table_index + 1
                width_remaining = max_width
                
                attempt_element_creation(current_table, width_remaining, id, subfactory, selected)
            else
                width_remaining = width_remaining - width_used
            end
        end
    end

    refresh_error_bar(player)
    refresh_subfactory_pane(player)
    refresh_production_pane(player)
end

-- Attempts to create and insert a new element into the table
-- The creation-function itself decides whether it will fit
function attempt_element_creation(table, width_remaining, id, subfactory, selected)
    local width_used
    if subfactory.name ~= nil and subfactory.icon == nil then
        width_used = create_label_element(table, width_remaining, id, subfactory, selected)
    elseif subfactory.icon ~= nil and subfactory.name == nil then
        width_used = create_sprite_element(table, width_remaining, id, subfactory, selected)
    else
        width_used = create_label_sprite_element(table, width_remaining, id, subfactory, selected)
    end
    return width_used
end

-- Constructs an element of the subfactory bar if there only is a name
function create_label_element(table, width_remaining, id, subfactory, selected)
    local button_width = (#subfactory.name*10) + 13
    if button_width > width_remaining then
        return 0
    else    
        local button = table.add{type="sprite-button", name="fp_sprite-button_subfactory_" .. id}
        local label = button.add{type="label", name="label_subfactory_" .. id, caption=subfactory.name}

        if selected then
            button.style = "fp_button_icon_blank"
            button.style.top_padding = 9
            button.style.left_padding = 8
        else
            button.style.height = 36
            button.style.top_padding = 7
            button.style.left_padding = 6
        end

        button.style.width = button_width 
        label.ignored_by_interaction = true
        label.style.font = "fp-label-mono"
        
        return button_width
    end
end

-- Constructs an element of the subfactory bar if there only is an icon
function create_sprite_element(table, width_remaining, id, subfactory, selected)
    local button_width = 36
    if button_width > width_remaining then
        return 0
    else  
        local button = create_sprite_button(table, "fp_sprite-button_subfactory_" .. id, subfactory)

        if selected then
            button.style = "fp_button_icon_blank"
        else
            button.style.height = 36
            button.style.width = 36
            set_padding(button, 0)
        end

        return button_width
    end
end

-- Constructs an element of the subfactory bar if there is both a name and an icon
function create_label_sprite_element(table, width_remaining, id, subfactory, selected)
    local button_width = (#subfactory.name*10) + 46
    if button_width > width_remaining then
        return 0
    else 
        local button = table.add{type="sprite-button", name="fp_sprite-button_subfactory_" .. id}
        local flow = button.add{type="flow", name="flow_subfactory_" .. id, direction="horizontal"}

        local sprite = create_sprite_button(flow, "sprite_subfactory_" .. id, subfactory)
        local label = flow.add{type="label", name="label_subfactory_" .. id, caption=subfactory.name}

        if selected then
            button.style = "fp_button_icon_blank"
            flow.style.top_padding = 2
            sprite.style.top_padding = 1
        else
            button.style.height = 36
            flow.style.top_padding = 0
            sprite.style.top_padding = 0
        end

        button.style.width = button_width
        button.style.top_padding = 0
        button.tooltip = sprite.tooltip
        flow.ignored_by_interaction = true

        sprite.style = "fp_button_icon_blank"
        sprite.style.height = 34
        sprite.style.width = 34
        label.style.font = "fp-label-mono"
        label.style.top_padding = 7

        return button_width
    end
end

-- Creates the sprite-button, checking if the sprite is still loaded (in case a mod is removed)
function create_sprite_button(table, name, subfactory)
    local sprite_path = "item/" .. subfactory.icon
    local tooltip = ""
    if not table.gui.is_valid_sprite_path(sprite_path) then
        sprite_path = "utility/danger_icon"
        tooltip = {"tooltip.sprite_missing"}
    end
    local button = table.add{type="sprite-button", name=name, sprite=sprite_path}
    button.tooltip = tooltip

    return button
end


-- Moves selection to the clicked element or shifts it's position left or right
function handle_subfactory_element_click(player, id, control, shift)
    local position = get_subfactory_gui_position(id)
    local change = false
    
    -- shift position to the right
    if not control and shift then
        if position ~= #global["subfactory_order"] then
            swap_subfactory_positions(global["subfactory_order"][position], global["subfactory_order"][position+1])
            change = true
        end

    -- shift position to the left
    elseif control and not shift then
        if position ~= 1 then
            swap_subfactory_positions(global["subfactory_order"][position], global["subfactory_order"][position-1])
            change = true
        end

    -- change selected subfactory
    elseif not control and not shift then
        if global["selected_subfactory_id"] ~= id then
            global["selected_subfactory_id"] = id
            change = true
        end
    end

    if change then
        global["current_activity"] = nil
        update_subfactory_order()
        refresh_main_dialog(player)
    end
end

-- Updates the GUI order of the individual subfactories
-- Kinda stupid implementation, but whatever
function update_subfactory_order()
    -- First, it simply assigns them to the index in the array that's equal to their position
    local count = 0
    local uncompressed_order = {}
    for id, subfactory in ipairs(get_subfactories()) do
        uncompressed_order[subfactory.gui_position] = id
        count = count + 1
    end

    -- Then, the empty index of the array is squashed
    global["subfactory_order"] = {}
    local i = 0
    while i < count do
        if uncompressed_order[i] ~= nil then
            table.insert(global["subfactory_order"], uncompressed_order[i])
        else
            count = count + 1
        end
        i = i + 1
    end
end
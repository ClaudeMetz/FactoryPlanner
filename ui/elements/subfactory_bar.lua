-- Creates the subfactory bar that includes all current subfactory buttons
function add_subfactory_bar_to(main_dialog, player)
    main_dialog.add{type="table", name="table_subfactory_bar", direction="horizontal", column_count = 10}
    refresh_main_dialog(player)
end


-- Refreshes the subfactory bar by reloading the data
function refresh_subfactory_bar(player)
    local subfactory_bar =  player.gui.center["main_dialog"]["table_subfactory_bar"]
    subfactory_bar.clear()

    -- selected_subfactory_id is 0 when there are no subfactories
    if global["selected_subfactory_id"] ~= 0 then
        for _, id in ipairs(global["subfactory_order"]) do
            local subfactory = get_subfactory(id)
            local table = subfactory_bar.add{type="table", name="table_subfactory_" .. id, column_count=2}
            local selected = (global["selected_subfactory_id"] == id)
            
            if subfactory.name ~= nil and subfactory.icon == nil then
                create_label_element(table, id, subfactory, selected)
            elseif subfactory.icon ~= nil and subfactory.name == nil then
                create_sprite_element(table, id, subfactory, selected)
            else
                create_label_sprite_element(table, id, subfactory, selected)
            end
        end
    end
end


-- Constructs an element of the subfactory bar if there is only a name
function create_label_element(table, id, subfactory, selected)
    if selected then
        local button = table.add{type="label", name="xbutton_subfactory_" .. id, caption=subfactory.name}
        button.style.height = 34
        button.style.top_padding = 7
        button.style.left_padding = 8
        button.style.right_padding = 8
        button.style.font = "fp-button-standard"
    else
        local button = table.add{type="button", name="xbutton_subfactory_" .. id, caption=subfactory.name}
        button.style.height = 34
        button.style.top_padding = 3
        button.style.font = "fp-button-standard"
    end
end

-- Constructs an element of the subfactory bar if there is only an icon
function create_sprite_element(table, id, subfactory, selected)
    if selected then
        local button = table.add{type="sprite", name="xbutton_subfactory_" .. id, sprite="item/" .. subfactory.icon}
        button.style.width = 34
        button.style.height = 30
        button.style.left_padding = 1
        button.style.right_padding = 3
    else
        local button = table.add{type="sprite-button", name="xbutton_subfactory_" .. id, sprite="item/" .. subfactory.icon}
        button.style.width = 34
        button.style.height = 34
    end
end

-- Constructs an element of the subfactory bar if there is both a name and an icon
function create_label_sprite_element(table, id, subfactory, selected)
    if selected then
        local button = table.add{type="flow", name="xbutton_subfactory_" .. id, column_count=2}
        button.style.left_padding = 8
        button.style.right_padding = 11

        button.add{type="sprite", name="sprite_subfactory_" .. id, sprite="item/" .. subfactory.icon}
        button["sprite_subfactory_" .. id].style.top_padding = 2
        button["sprite_subfactory_" .. id].style.height = 34
        button["sprite_subfactory_" .. id].style.width = 34
        button["sprite_subfactory_" .. id].ignored_by_interaction = true
        button.add{type="label", name="label_subfactory_" .. id, caption=subfactory.name}
        button["label_subfactory_" .. id].style.top_padding = 6
        button["label_subfactory_" .. id].style.left_padding = 0
        button["label_subfactory_" .. id].ignored_by_interaction = true
        button["label_subfactory_" .. id].style.font = "fp-button-standard"
    else
        local button = table.add{type="button", name="xbutton_subfactory_" .. id, caption=""}
        button.style.font = "fp-button-standard"
        button.style.height = 34
        button.style.top_padding = 0
        button.style.width = determine_pixelsize_of(subfactory.name) + 50

        local flow = button.add{type="flow", name="flow_subfactory_" .. id, column_count=2}
        flow.ignored_by_interaction = true

        flow.add{type="sprite", name="sprite_subfactory_" .. id, sprite="item/" .. subfactory.icon}
        flow["sprite_subfactory_" .. id].style.height = 34
        flow["sprite_subfactory_" .. id].style.width = 34
        flow.add{type="label", name="label_subfactory_" .. id, caption=subfactory.name}
        flow["label_subfactory_" .. id].style.top_padding = 2
        flow["label_subfactory_" .. id].style.left_padding = 0
        flow["label_subfactory_" .. id].style.font = "fp-button-standard"
    end
end


-- Moves selection to the clicked element or shifts it's position left or right
function handle_subfactory_element_click(player, id, control, shift)
    local position = get_subfactory_gui_position(id)
    local change = true
    
    -- shift position to the right
    if not control and shift then
        if position ~= #global["subfactory_order"] then
            swap_subfactory_positions(global["subfactory_order"][position], global["subfactory_order"][position+1])
        end
    -- shift position to the left
    elseif control and not shift then
        if position ~= 1 then
            swap_subfactory_positions(global["subfactory_order"][position], global["subfactory_order"][position-1])
        end
    -- change selected subfactory
    elseif not control and not shift then
        if global["selected_subfactory_id"] == id then
            change = false
        else
            global["selected_subfactory_id"] = id
        end
    end

    if change then
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
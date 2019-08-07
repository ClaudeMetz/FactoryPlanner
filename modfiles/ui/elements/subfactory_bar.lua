-- Creates the subfactory bar that includes all current subfactory buttons
function add_subfactory_bar_to(main_dialog)
    local subfactory_bar = main_dialog.add{type="scroll-pane", name="scroll-pane_subfactory_bar", direction="vertical"}
    subfactory_bar.style.maximal_height = 82
    subfactory_bar.style.bottom_margin = 8
    subfactory_bar.style.left_margin = 6
    subfactory_bar.style.horizontally_stretchable = true
    subfactory_bar.style.vertically_squashable = false
    subfactory_bar.horizontal_scroll_policy = "never"

    local table_subfactories = subfactory_bar.add{type="table", name="table_subfactories", column_count = 1}
    table_subfactories.style.vertical_spacing = 4

    refresh_subfactory_bar(game.get_player(main_dialog.player_index), true)
end


-- Refreshes the subfactory bar by reloading the data
function refresh_subfactory_bar(player, full_refresh)
    local ui_state = get_ui_state(player)
    local table_subfactories =  player.gui.screen["fp_frame_main_dialog"]["scroll-pane_subfactory_bar"]["table_subfactories"]
    table_subfactories.clear()

    local max_width = ui_state.main_dialog_dimensions.width * 0.8
    local width_remaining = 0
    local current_table_index = 0
    local current_table = nil

    if ui_state.context.subfactory ~= nil then
        for _, subfactory in ipairs(Factory.get_in_order(ui_state.context.factory, "Subfactory")) do
            -- Tries to insert new element, if it doesn't fit, a new row is created and creation is reattempted
            -- First one is supposed to fail to create the first table
            local selected = (ui_state.context.subfactory.id == subfactory.id)
            local width_used = attempt_element_creation(current_table, width_remaining, subfactory, selected)

            if width_used == 0 then
                current_table = table_subfactories.add{type="table", name="table_subfactories_" .. current_table_index, 
                  column_count = 30}
                current_table.style.horizontal_spacing = 6
                current_table_index = current_table_index + 1
                width_remaining = max_width
                
                attempt_element_creation(current_table, width_remaining, subfactory, selected)
            else
                width_remaining = width_remaining - width_used
            end
        end
    end

    if full_refresh then
        refresh_error_bar(player)
        refresh_subfactory_pane(player)
        refresh_production_pane(player)
    end
end

-- Attempts to create and insert a new element into the table
-- The creation-function itself decides whether it will fit
function attempt_element_creation(table, width_remaining, subfactory, selected)
    local width_used

    if subfactory.name ~= "" and subfactory.icon == nil then
        width_used = create_label_element(table, width_remaining, subfactory, selected)
    elseif subfactory.icon ~= nil and subfactory.name == "" then
        width_used = create_sprite_element(table, width_remaining, subfactory, selected)
    else
        width_used = create_label_sprite_element(table, width_remaining, subfactory, selected)
    end

    return width_used
end

-- Constructs an element of the subfactory bar if there only is a name
function create_label_element(table, width_remaining, subfactory, selected)
    local button_width = (#subfactory.name * 9) + 20
    if button_width > width_remaining then
        return 0
    else    
        local button = table.add{type="sprite-button", name="fp_sprite-button_subfactory_" .. subfactory.id,
          mouse_button_filter={"left-and-right"}}
        local label = button.add{type="label", name="label_subfactory_" .. subfactory.id, caption=subfactory.name}

        button.style = selected and "fp_subfactory_sprite_button_selected" or "fp_subfactory_sprite_button"
        button.style.width = button_width
        button.style.top_padding = 4
        button.style.left_padding = 6
        ui_util.add_tutorial_tooltip(button, "subfactory", false, false)
        
        label.style.font = "fp-font-mono-15p"
        label.style.font_color = {}  -- black
        label.ignored_by_interaction = true
        
        return button_width
    end
end

-- Constructs an element of the subfactory bar if there only is an icon
function create_sprite_element(table, width_remaining, subfactory, selected)
    local button_width = 38
    if button_width > width_remaining then
        return 0
    else  
        local button = create_sprite_button(table, "fp_sprite-button_subfactory_" .. subfactory.id, subfactory)

        button.style = selected and "fp_subfactory_sprite_button_selected" or "fp_subfactory_sprite_button"
        button.style.width = button_width
        
        return button_width
    end
end

-- Constructs an element of the subfactory bar if there is both a name and an icon
function create_label_sprite_element(table, width_remaining, subfactory, selected)
    local button_width = (#subfactory.name * 9) + 60
    if button_width > width_remaining then
        return 0
    else
        local button = table.add{type="sprite-button", name="fp_sprite-button_subfactory_" .. subfactory.id,
          mouse_button_filter={"left-and-right"}}
        local flow = button.add{type="flow", name="flow_subfactory_" .. subfactory.id, direction="horizontal"}
        local sprite = create_sprite_button(flow, "sprite_subfactory_" .. subfactory.id, subfactory)
        local label = flow.add{type="label", name="label_subfactory_" .. subfactory.id, caption=subfactory.name}

        button.style = selected and "fp_subfactory_sprite_button_selected" or "fp_subfactory_sprite_button"
        button.tooltip = sprite.tooltip
        button.style.width = button_width

        flow.ignored_by_interaction = true
        flow.style.top_padding = -2
        
        sprite.style = "fp_button_icon_large_blank"
        sprite.style.height = 34
        sprite.style.width = 34
        sprite.style.top_padding = 1
        sprite.style.left_margin = 5

        label.style.font = "fp-font-mono-15p"
        label.style.font_color = {}  -- black
        label.style.top_padding = 6
        label.style.left_padding = 3

        return button_width
    end
end

-- Creates the sprite-button, checking if the sprite is still loaded (in case a mod is removed)
function create_sprite_button(table, name, subfactory)
    local sprite_path = subfactory.icon.type .. "/" .. subfactory.icon.name
    local tooltip = ""
    if not table.gui.is_valid_sprite_path(sprite_path) then
        sprite_path = "utility/danger_icon"
        tooltip = {"tooltip.sprite_missing"}
    end
    local button = table.add{type="sprite-button", name=name, sprite=sprite_path, 
      tooltip=tooltip, mouse_button_filter={"left-and-right"}}

    if tooltip == "" then ui_util.add_tutorial_tooltip(button, "subfactory", false, false)
    else ui_util.add_tutorial_tooltip(button, "subfactory", true, false) end

    return button
end


-- Moves selection to the clicked element, edits it, or shifts it's position left or right
function handle_subfactory_element_click(player, subfactory_id, click, direction)
    local ui_state = get_ui_state(player)
    local subfactory = Factory.get(ui_state.context.factory, "Subfactory", subfactory_id)

    -- Shift subfactory in the given direction
    if direction ~= nil then
        Factory.shift(ui_state.context.factory, subfactory, direction)
        refresh_subfactory_bar(player, false)

    else
        old_subfactory = ui_state.context.subfactory
        data_util.context.set_subfactory(player, subfactory)
        -- Change selected subfactory
        if click == "left" then
            -- Reset Floor when clicking on selected subfactory
            if old_subfactory == subfactory then
                subfactory.selected_floor = Subfactory.get(subfactory, "Floor", 1)
            end
            
            ui_state.current_activity = nil
            update_calculations(player, subfactory)

        -- Edit clicked subfactory
        elseif click == "right" then
            enter_modal_dialog(player, {type="subfactory", object=subfactory, submit=true, delete=true})
        end
    end
end
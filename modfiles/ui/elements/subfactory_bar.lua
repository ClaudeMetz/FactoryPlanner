subfactory_bar = {}

-- ** LOCAL UTIL **
-- Attempts to create and insert a new element into the table
local function attempt_element_creation(player, table, width_remaining, subfactory, selected)
    if table == nil then return 0 end
    local width_used, tooltip = 0, ""

    local style = selected and "fp_subfactory_sprite_button_selected" or "fp_subfactory_sprite_button"
    local button = table.add{type="button", name="fp_sprite-button_subfactory_" .. subfactory.id,
      style=style, mouse_button_filter={"left-and-right"}}

    local flow = button.add{type="flow", direction="horizontal"}
    flow.ignored_by_interaction = true

    -- Icon sprite
    if subfactory.icon ~= nil then
        -- Determine sprite path, check if it's valid
        local sprite_path = subfactory.icon.type .. "/" .. subfactory.icon.name
        if not player.gui.is_valid_sprite_path(sprite_path) then
            sprite_path = "utility/danger_icon"
            tooltip = {"fp.sprite_missing"}
        end

        local sprite = flow.add{type="label", caption="[font=fp-font-bold-20p][img=" .. sprite_path .. "][/font]"}
        sprite.style.height = 34
        sprite.style.left_padding = 1
        sprite.style.top_padding = 1

        width_used = width_used + 38
    end

    -- Name label
    if subfactory.name ~= "" then
        flow.style.left_padding = 2
        local label = flow.add{type="label", caption="[font=fp-font-mono-16p][color=0,0,0]"
          .. subfactory.name .. "[/color][/font]"}
        label.style.left_padding = 2
        label.style.top_padding = 4

        width_used = width_used + (#subfactory.name * 10) + 15
    end

    -- Adjust button width when both icon and name are used
    if subfactory.icon ~= nil and subfactory.name ~= "" then
        width_used = width_used - 5
    end

    -- Finish button setup if it still fits in the current line, else destroy it
    if width_remaining < width_used then
        button.destroy()
        return 0
    else
        button.style.width = width_used
        button.tooltip = {"", tooltip, ui_util.tutorial_tooltip(player, nil, "subfactory", (tooltip ~= ""))}
        return width_used
    end
end


-- ** TOP LEVEL **
-- Creates the subfactory bar that includes all current subfactory buttons
function subfactory_bar.add_to(main_dialog)
    local flow_subfactory_bar = main_dialog.add{type="scroll-pane", name="scroll-pane_subfactory_bar",
      direction="vertical"}
    flow_subfactory_bar.style.maximal_height = 88
    flow_subfactory_bar.style.margin = {0, 2, 8, 6}
    flow_subfactory_bar.style.horizontally_stretchable = true
    flow_subfactory_bar.style.vertically_squashable = false
    flow_subfactory_bar.horizontal_scroll_policy = "never"

    local table_subfactories = flow_subfactory_bar.add{type="table", name="table_subfactories", column_count=1}
    table_subfactories.style.vertical_spacing = 4

    subfactory_bar.refresh(game.get_player(main_dialog.player_index), true)
end

-- Refreshes the subfactory bar by reloading the data
function subfactory_bar.refresh(player, full_refresh)
    local ui_state = get_ui_state(player)
    local table_subfactories = player.gui.screen["fp_frame_main_dialog"]
      ["scroll-pane_subfactory_bar"]["table_subfactories"]
    table_subfactories.clear()

    local max_width = ui_state.main_dialog_dimensions.width * 0.94
    local table_spacing = 6  -- constant

    local width_remaining = 0
    local current_table_index, current_table = 0, nil

    if ui_state.context.subfactory ~= nil then
        for _, subfactory in ipairs(Factory.get_in_order(ui_state.context.factory, "Subfactory")) do
            -- Tries to insert new element, if it doesn't fit, a new row is created and creation is re-attempted
            local selected = (ui_state.context.subfactory.id == subfactory.id)
            -- The first one is supposed to fail (width_remaining = 0) to create the first table
            local width_used = attempt_element_creation(player, current_table, width_remaining, subfactory, selected)

            if width_used == 0 then
                current_table = table_subfactories.add{type="table", name="table_subfactories_"
                  .. current_table_index, column_count=100}
                current_table.style.horizontal_spacing = 6
                current_table_index = current_table_index + 1
                width_remaining = max_width

                attempt_element_creation(player, current_table, width_remaining, subfactory, selected)
            else
                width_remaining = width_remaining - width_used - table_spacing
            end
        end
    end

    if full_refresh then
        error_bar.refresh(player)
        subfactory_pane.refresh(player)
        production_titlebar.refresh(player)
    end
end


-- Moves selection to the clicked element, edits it, or shifts it's position left or right
function subfactory_bar.handle_subfactory_element_click(player, subfactory_id, click, direction, action)
    local ui_state = get_ui_state(player)
    local subfactory = Factory.get(ui_state.context.factory, "Subfactory", subfactory_id)

    -- Shift subfactory in the given direction
    if direction ~= nil then
        if Factory.shift(ui_state.context.factory, subfactory, direction) then
            subfactory_bar.refresh(player, false)
        else
            local direction_string = (direction == "negative") and {"fp.left"} or {"fp.right"}
            local message = {"fp.error_list_item_cant_be_shifted", {"fp.subfactory"}, direction_string}
            ui_util.message.enqueue(player, message, "error", 1, false)
        end

        main_dialog.refresh_current_activity(player)

    -- Change selected subfactory
    else
        old_subfactory = ui_state.context.subfactory
        ui_util.context.set_subfactory(player, subfactory)

        -- Reset Floor when clicking on selected subfactory
        if click == "left" and old_subfactory == subfactory then
            production_titlebar.handle_floor_change_click(player, "top")

        elseif click == "right" then
            if action == "edit" then
                modal_dialog.enter(player, {type="subfactory", submit=true,
                  delete=true, modal_data={subfactory=subfactory}})
            elseif action == "delete" then
                actionbar.handle_subfactory_deletion(player)
            end

        else  -- refresh if the selected subfactory is indeed changed
            ui_state.current_activity = nil
            main_dialog.refresh(player)
        end
    end
end
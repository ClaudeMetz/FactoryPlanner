production_box = {}

-- ** LOCAL UTIL **
local function refresh_production(player)
    local subfactory = data_util.get("context", player).subfactory
    if subfactory and subfactory.valid and main_dialog.is_in_focus(player) then
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


-- ** TOP LEVEL **
production_box.gui_events = {
    on_gui_click = {
        {
            name = "fp_sprite-button_production_refresh",
            handler = (function(player, _, _)
                refresh_production(player)
            end)
        },
        {
            pattern = "^fp_button_production_floor_[a-z]+$",
            handler = (function(player, element, _)
                local destination = string.gsub(element.name, "fp_button_production_floor_", "")
                production_box.change_floor(player, destination)
            end)
        }
    }
}

production_box.misc_events = {
    fp_refresh_production = (function(player, _)
        refresh_production(player)
    end),

    fp_floor_up = (function(player, _)
        production_box.change_floor(player, "up")
    end)
}

function production_box.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.production_box = {}

    local parent_flow = main_elements.flows.right_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
    frame_vertical.style.vertically_stretchable = true
    frame_vertical.style.horizontally_stretchable = true
    main_elements.production_box["vertical_frame"] = frame_vertical

    local subheader = frame_vertical.add{type="frame", direction="horizontal", style="subheader_frame"}
    subheader.style.maximal_height = 100  -- large value to nullify maximal_height
    subheader.style.padding = {8, 8, 6, 8}

    local button_refresh = subheader.add{type="sprite-button", name="fp_sprite-button_production_refresh",
      sprite="utility/refresh", style="tool_button", tooltip={"fp.refresh_production"}, mouse_button_filter={"left"}}
    main_elements.production_box["refresh_button"] = button_refresh

    local label_title = subheader.add{type="label", caption={"fp.production"}, style="frame_title"}
    label_title.style.padding = 0
    label_title.style.left_margin = 6

    local label_level = subheader.add{type="label"}
    label_level.style.margin = {0, 12, 0, 6}
    main_elements.production_box["level_label"] = label_level

    local button_floor_up = subheader.add{type="button", name="fp_button_production_floor_up", caption={"fp.floor_up"},
      tooltip={"fp.floor_up_tt"}, style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    main_elements.production_box["floor_up_button"] = button_floor_up
    local button_floor_top = subheader.add{type="button", name="fp_button_production_floor_top",
      caption={"fp.floor_top"}, tooltip={"fp.floor_top_tt"}, style="fp_button_rounded_mini",
      mouse_button_filter={"left"}}
    main_elements.production_box["floor_top_button"] = button_floor_top

    subheader.add{type="empty-widget", style="flib_horizontal_pusher"}

    local table_view_state = view_state.build(player, subheader)
    main_elements.production_box["view_state_table"] = table_view_state

    local label_instruction = frame_vertical.add{type="label", caption={"fp.production_instruction"},
      style="bold_label"}
    label_instruction.style.margin = 20
    main_elements.production_box["instruction_label"] = label_instruction

    production_box.refresh(player)
    production_table.build(player)
end

function production_box.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local production_box_elements = ui_state.main_elements.production_box

    local subfactory = ui_state.context.subfactory
    local subfactory_valid = subfactory and subfactory.valid

    local current_level = (subfactory_valid) and subfactory.selected_floor.level or 1
    local any_lines_present = (subfactory_valid) and (subfactory.selected_floor.Line.count > 0) or false
    local archive_open = (ui_state.flags.archive_open)

    production_box_elements.refresh_button.enabled = (not archive_open and subfactory_valid and any_lines_present)
    production_box_elements.instruction_label.visible = (subfactory_valid and not any_lines_present)

    production_box_elements.level_label.caption = (not subfactory_valid) and ""
      or {"fp.bold_label", {"fp.two_word_title", {"fp.level"}, current_level}}

    production_box_elements.floor_up_button.visible = (subfactory_valid)
    production_box_elements.floor_up_button.enabled = (current_level > 1)

    production_box_elements.floor_top_button.visible = (subfactory_valid)
    production_box_elements.floor_top_button.enabled = (current_level > 2)

    view_state.refresh(player, production_box_elements.view_state_table)
    production_box_elements.view_state_table.visible = (subfactory_valid)
end


-- Changes the floor to either be the top one or the one above the current one
function production_box.change_floor(player, destination)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory
    local floor = ui_state.context.floor

    if subfactory == nil or floor == nil then return end

    local selected_floor = nil
    if destination == "up" and floor.level > 1 then
        selected_floor = floor.origin_line.parent
    elseif destination == "top" then
        selected_floor = Subfactory.get(subfactory, "Floor", 1)
    end

    -- Only need to refresh if the floor was indeed changed
    if selected_floor ~= nil then
        ui_util.context.set_floor(player, selected_floor)

        -- Remove previous floor if it has no recipes
        local floor_removed = Floor.remove_if_empty(floor)

        if floor_removed then calculation.update(player, subfactory) end
        main_dialog.refresh(player, {"production_box", "production_table"})
    end
end
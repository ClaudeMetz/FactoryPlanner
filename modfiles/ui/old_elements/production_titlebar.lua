production_titlebar = {}

-- ** LOCAL UTIL **
-- Moves on the selection until it is on an enabled state (at least 1 view needs to be enabled)
-- (Not useful currently as all views are enabled, but it was in the past)
local function correct_view_state(view_state, id_to_select)
    while true do
        view = view_state[id_to_select]
        if view.enabled then
            view.selected = true
            view_state.selected_view = view
            break
        else
            id_to_select = (id_to_select % #view_state) + 1
        end
    end
end

-- Refreshes the current view state
local function refresh_view_state(player, subfactory)
    local player_table = get_table(player)
    local timescale = ui_util.format_timescale(subfactory.timescale, true, false)
    local bl_caption = (player_table.settings.belts_or_lanes == "belts") and {"fp.cbelts"} or {"fp.clanes"}
    local bl_sprite = prototyper.defaults.get(player, "belts").rich_text
    local view_state = {
        [1] = {
            name = "items_per_timescale",
            caption = {"", {"fp.citems"}, "/", timescale},
            enabled = true,
            selected = true
        },
        [2] = {
            name = "belts_or_lanes",
            caption = {"", bl_sprite, " ", bl_caption},
            enabled = true,
            selected = false
        },
        [3] = {
            name = "items_per_second_per_machine",
            caption = {"", {"fp.citems"}, "/", {"fp.unit_second"}, "/[img=fp_generic_assembler]"},
            enabled = true,
            selected = false
        }
    }
    view_state.selected_view = view_state[1]

    -- Conserves the selection state from the previous view_state, if available
    if player_table.ui_state.view_state ~= nil then
        local id_to_select = nil
        for i, view in ipairs(player_table.ui_state.view_state) do
            if view.selected then id_to_select = i
            else view_state[i].selected = false end
        end
        correct_view_state(view_state, id_to_select)
    end

    player_table.ui_state.view_state = view_state
end


-- ** TOP LEVEL **
-- Creates the production pane that displays
function production_titlebar.add_to(frame_main_dialog)
    local flow = frame_main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}

    -- Production titlebar
    local table_titlebar = flow.add{type="table", name="table_production_titlebar", column_count=7}
    table_titlebar.style.bottom_margin = 8

    -- Refresh button
    local button_refresh = table_titlebar.add{type="sprite-button", name="fp_sprite-button_refresh_production",
      sprite="utility/refresh", style="fp_sprite_button", tooltip={"fp.refresh_production"}}
    button_refresh.style.width = 22
    button_refresh.style.height = 22
    button_refresh.style.left_margin = 8

    -- Title
    local title = table_titlebar.add{type="label", name="label_production_pane_title",
      caption={"", "  ", {"fp.production"}, " "}}
    title.style.font = "fp-font-20p"
    title.style.top_padding = 2
    title.style.left_margin = 0

    -- Navigation
    local label_level = table_titlebar.add{type="label", name="label_production_titlebar_level", caption=""}
    label_level.style.font = "fp-font-bold-15p"
    label_level.style.top_padding = 4
    label_level.style.left_padding = 10

    local table_navigation = table_titlebar.add{type="table", name="table_production_titlebar_navigation", column_count=2}
    table_navigation.add{type="button", name="fp_button_floor_up", caption={"fp.go_up"},
      style="fp_button_mini", mouse_button_filter={"left"}}
    table_navigation.add{type="button", name="fp_button_floor_top", caption={"fp.to_the_top"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- Spacer
    local spacer = table_titlebar.add{type="flow", name="flow_spacer", direction="horizontal"}
    spacer.style.horizontally_stretchable = true

    -- TopLevelItem-amount toggle
    local button_toggle = table_titlebar.add{type="button", name="fp_button_item_amount_toggle",
      caption={"fp.item_amount_toggle"}, tooltip={"fp.item_amount_toggle_tt"},
      mouse_button_filter={"left"}}
    button_toggle.style.right_margin = 16

    -- View selection
    local table_view_selection = table_titlebar.add{type="table", name="table_production_titlebar_view_selection",
      column_count=3}
    table_view_selection.style.horizontal_spacing = 0

    -- Captions will be set appropriately at runtime
    table_view_selection.add{type="button", name="fp_button_production_titlebar_view_items_per_timescale"}
    -- (The tooltip for this is set dynamically)

    table_view_selection.add{type="button", name="fp_button_production_titlebar_view_belts_or_lanes"}
    -- (The tooltip for this is set dynamically)

    table_view_selection.add{type="button", name="fp_button_production_titlebar_view_items_per_second_per_machine",
      tooltip={"", {"fp.items_per_second_per_machine"}, "\n", {"fp.cycle_production_views"}}}


    -- Info label
    local info = flow.add{type="label", name="label_production_info",
      caption={"", "   (",  {"fp.production_info"}, ")"}}
    info.visible = false

    -- Main production pane
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane_production_pane", direction="vertical"}
    scroll_pane.style.left_margin = 4
    scroll_pane.style.right_margin = -4
    scroll_pane.style.extra_left_margin_when_activated = -4
    scroll_pane.style.extra_top_margin_when_activated = -4
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_squashable = true

    production_titlebar.refresh(game.get_player(frame_main_dialog.player_index))
end

-- Refreshes the production pane (titlebar + table)
function production_titlebar.refresh(player)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
    -- Cuts function short if the approriate GUI's haven't been initialized yet
    if not (frame_main_dialog and frame_main_dialog["flow_production_pane"]) then return end

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory

    local table_titlebar = frame_main_dialog["flow_production_pane"]["table_production_titlebar"]
    local table_view = table_titlebar["table_production_titlebar_view_selection"]
    -- Only show the titlebar if a valid subfactory is shown
    table_titlebar.visible = (subfactory ~= nil and subfactory.valid)

    -- Configure Floor labels and buttons
    if subfactory ~= nil and subfactory.valid then
        local floor = ui_state.context.floor

        -- Refresh button
        local button_refresh = table_titlebar["fp_sprite-button_refresh_production"]
        button_refresh.visible = (floor.Line.count > 0)

        -- Level indicator
        local label_level = table_titlebar["label_production_titlebar_level"]
        label_level.caption = {"", {"fp.level"}, " ", floor.level, "  "}
        label_level.visible = (floor.Line.count > 0)

        -- Navigation
        local table_navigation = table_titlebar["table_production_titlebar_navigation"]
        table_navigation["fp_button_floor_up"].visible = (floor.level > 1)
        table_navigation["fp_button_floor_top"].visible = (floor.level > 2)

        -- TopLevelItem-amount toggle
        table_titlebar["fp_button_item_amount_toggle"].visible = (floor.level > 1)

        -- Update the dynamic parts of the view state buttons
        local state_existed = (ui_state.view_state ~= nil)
        refresh_view_state(player, subfactory)

        -- Refresh subfactory pane to update it with the selected state
        if not state_existed then subfactory_pane.refresh(player) end

        for _, view in ipairs(ui_state.view_state) do
            local button = table_view["fp_button_production_titlebar_view_" .. view.name]
            button.caption = view.caption

            -- Update the tooltip based on current settings
            -- The "items_per_second_per_machine"-tooltip doesn't need to be updated according to any settings
            if view.name == "items_per_timescale" then
                local timescale = ui_util.format_timescale(subfactory.timescale, true, true)
                button.tooltip = {"", {"fp.items_per_timescale"}, " ", timescale, ".",
                  "\n", {"fp.cycle_production_views"}}
            elseif view.name == "belts_or_lanes" then
                local belts_lanes_label = (player_table.settings.belts_or_lanes == "belts")
                  and {"fp.belts"} or {"fp.lanes"}
                button.tooltip = {"", {"fp.belts_or_lanes", belts_lanes_label}, "\n", {"fp.cycle_production_views"}}
            end

            -- It's disabled if it's selected or not enabled by the view
            button.enabled = (not view.selected and view.enabled)
            button.style = view.selected and "fp_view_selection_button_selected" or "fp_view_selection_button"
        end
    end

    production_table.refresh(player)
end


-- Handles a click on a button that changes the viewed floor of a subfactory
function production_titlebar.handle_floor_change_click(player, destination)
    local ui_state = get_ui_state(player)
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

        -- Remove floor if no recipes have been added to it
        Floor.remove_if_empty(floor)

        calculation.update(player, subfactory, true)
    end
end


-- Toggles the button-style and ui_state of floor_total
function production_titlebar.toggle_floor_total_display(player, button)
    local flags = get_flags(player)

    if button.style.name == "button" then
        flags.floor_total = true
        button.style = "fp_button_selected"
        button.style.right_margin = 16
    else
        flags.floor_total = false
        button.style = "button"
    end

    main_dialog.refresh(player)
end


-- Sets the current view to the given view (If no view if provided, it sets it to the next enabled one)
function production_titlebar.change_view_state(player, view_name)
    local ui_state = get_ui_state(player)

    -- Return if table_view_selection does not exist yet (this is really crappy and ugly)
    local frame_main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if not frame_main_dialog or not frame_main_dialog.visible then return end
    local table_titlebar = frame_main_dialog["flow_production_pane"]["table_production_titlebar"]
    if not (frame_main_dialog["flow_production_pane"] and frame_main_dialog["flow_production_pane"]
      ["table_production_titlebar"] and table_titlebar["table_production_titlebar_view_selection"]) then return end

    -- Only change the view_state if it exists and is visible
    if ui_state.view_state ~= nil and table_titlebar.visible then
        local id_to_select = nil
        for i, view in ipairs(ui_state.view_state) do
            -- Move selection on by one if no view_name is provided
            if view_name == nil and view.selected then
                view.selected = false
                id_to_select = (i % #ui_state.view_state) + 1
                break

            else
                -- Otherwise, select the given view
                if view.name == view_name then id_to_select = i
                else view.selected = false end
            end
        end
        correct_view_state(ui_state.view_state, id_to_select)
    end

    main_dialog.refresh(player)
end
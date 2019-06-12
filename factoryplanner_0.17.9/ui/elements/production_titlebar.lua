-- Creates the production pane that displays 
function add_production_pane_to(main_dialog)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}

    -- Production titlebar
    local table_titlebar = flow.add{type="table", name="table_production_titlebar", column_count=5}
    table_titlebar.style.bottom_margin = 8

    -- Title
    local title = table_titlebar.add{type="label", name="label_production_pane_title", 
      caption={"", "  ", {"label.production"}, " "}}
    title.style.font = "fp-font-20p"
    title.style.top_padding = 2

    -- Navigation
    local label_level = table_titlebar.add{type="label", name="label_production_titlebar_level", caption=""}
    label_level.style.font = "fp-font-bold-15p"
    label_level.style.top_padding = 4

    local table_navigation = table_titlebar.add{type="table", name="table_production_titlebar_navigation", column_count=2}
    table_navigation.add{type="button", name="fp_button_floor_up", caption={"label.go_up"},
      style="fp_button_mini", mouse_button_filter={"left"}}
    table_navigation.add{type="button", name="fp_button_floor_top", caption={"label.to_the_top"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- View selection
    local spacer = table_titlebar.add{type="flow", name="flow_spacer", direction="horizontal"}
    spacer.style.horizontally_stretchable = true

    local table_view_selection = table_titlebar.add{type="table", name="table_production_titlebar_view_selection",
      column_count=3}
    table_view_selection.style.horizontal_spacing = 0

    -- Captions will be set appropriately at runtime
    table_view_selection.add{type="button", name="fp_button_production_titlebar_view_items_per_timescale",
      tooltip={"", {"tooltip.items_per_timescale"}, "\n", {"tooltip.cycle_production_views"}}}

    local button_bl = table_view_selection.add{type="button", name="fp_button_production_titlebar_view_belts_or_lanes",
    tooltip={"", {"tooltip.belts_or_lanes"}, "\n", {"tooltip.cycle_production_views"}}}
    local flow_bl = button_bl.add{type="flow", name="flow_belts_or_lanes", direction="horizontal"}
    flow_bl.ignored_by_interaction = true
    flow_bl.style.height = 20
    flow_bl.style.vertical_align = "center"
    local sprite_bl = flow_bl.add{type="sprite", name="sprite_belts_or_lanes"}
    sprite_bl.style.height = 20
    sprite_bl.style.width = 20
    sprite_bl.style.stretch_image_to_widget_size = true
    local label_bl = flow_bl.add{type="label", name="label_belts_or_lanes"}
    ui_util.set_label_color(label_bl, "black")
    label_bl.style.font = "default-semibold"

    table_view_selection.add{type="button", name="fp_button_production_titlebar_view_items_per_second",
      tooltip={"", {"tooltip.items_per_second"}, "\n", {"tooltip.cycle_production_views"}}}


    -- Info label
    local info = flow.add{type="label", name="label_production_info", 
      caption={"", "   (",  {"label.production_info"}, ")"}}
    info.visible = false

    -- Main production pane
    local scroll_pane = flow.add{type="scroll-pane", name="scroll-pane_production_pane", direction="vertical"}
    scroll_pane.style.left_margin = 4
    scroll_pane.style.extra_left_margin_when_activated = -4
    scroll_pane.style.extra_top_margin_when_activated = -4
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_squashable = true

    local column_count = 7
    local table = scroll_pane.add{type="table", name="table_production_pane",  column_count=column_count}
    table.style = "table_with_selection"
    table.style.horizontal_spacing = 16
    table.style.top_padding = 0
    table.style.left_margin = 6
    for i=1, column_count do
        if i < 5 then table.style.column_alignments[i] = "middle-center"
        else table.style.column_alignments[i] = "middle-left" end
    end

    refresh_production_pane(game.get_player(main_dialog.player_index))
end

-- Refreshes the production pane (titlebar + table)
function refresh_production_pane(player)
    local main_dialog = player.gui.center["fp_frame_main_dialog"]
    -- Cuts function short if the approriate GUI's haven't been initialized yet
    if not (main_dialog and main_dialog["flow_production_pane"]) then return end

    local player_table = get_table(player)
    local ui_state = player_table.ui_state
    local subfactory = ui_state.context.subfactory

    local table_titlebar = main_dialog["flow_production_pane"]["table_production_titlebar"]
    local table_view = table_titlebar["table_production_titlebar_view_selection"]
    -- Only show the titlebar if a valid subfactory is shown
    table_titlebar.visible = (subfactory ~= nil and subfactory.valid)

    -- Configure Floor labels and buttons
    if subfactory ~= nil and subfactory.valid then        
        local floor = ui_state.context.floor

        table_titlebar["table_production_titlebar_navigation"].visible = (floor.level > 1)
        if floor.Line.count > 0 then
            table_titlebar["label_production_titlebar_level"].caption = {"", {"label.level"}, " ", floor.level, "  "}
        end

        -- Configure view buttons
        table_view.visible = (floor.Line.count > 0)
        
        -- Update the dynamic parts of the view state buttons
        refresh_view_state(player, subfactory)
        for _, view in ipairs(ui_state.view_state) do
            local button = table_view["fp_button_production_titlebar_view_" .. view.name]

            if view.name == "belts_or_lanes" then
                local flow = button["flow_belts_or_lanes"]
                flow["label_belts_or_lanes"].caption = view.caption
                flow["sprite_belts_or_lanes"].sprite = "entity/" .. player_table.preferences.preferred_belt_name
                flow.style.left_padding = (player_table.settings.belts_or_lanes == "Belts") and 6 or 4
            else
                button.caption = view.caption
            end
            button.enabled = view.enabled
            button.style = view.selected and "fp_view_selection_button_selected" or "fp_view_selection_button"
        end
    end

    refresh_production_table(player)
end


-- Handles a click on a button that changes the viewed floor of a subfactory
function handle_floor_change_click(player, destination)
    local context = get_context(player)
    local subfactory = context.subfactory
    local floor = context.floor

    local selected_floor = nil
    if destination == "up" then
        selected_floor = floor.origin_line.parent
    elseif destination == "top" then
        selected_floor = Subfactory.get(subfactory, "Floor", 1)
    end
    data_util.context.set_floor(player, selected_floor)

    -- Remove floor if no recipes have been added to it
    if floor.level > 1 and floor.Line.count == 1 then
        floor.origin_line.subfloor = nil
        Subfactory.remove(subfactory, floor)
    end

    update_calculations(player, subfactory)
    refresh_production_pane(player)
end


-- Refreshes the current view state
function refresh_view_state(player, subfactory)
    local player_table = get_table(player)
    local timescale = ui_util.format_timescale(subfactory.timescale, true)
    local view_state = {
        [1] = {
            name = "items_per_timescale",
            caption = {"", {"button-text.items"}, "/", timescale},
            enabled = true,
            selected = true
        },
        [2] = {
            name = "belts_or_lanes",
            caption = (player_table.settings.belts_or_lanes == "Belts") 
                and {"button-text.belts"} or {"button-text.lanes"},
            enabled = true,
            selected = false
        },
        [3] = {
            name = "items_per_second",
            caption = {"", {"button-text.items"}, "/s"},
            enabled = (timescale ~= "s"),
            selected = false
        },
        selected_view_id = 1
    }

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

-- Sets the current view to the given view (If no view if provided, it sets it to the next enabled one)
function change_view_state(player, view_name)
    local ui_state = get_ui_state(player)

    -- Return if table_view_selection does not exist yet (this is really crappy and ugly)
    local main_dialog = player.gui.center["fp_frame_main_dialog"]
    if not main_dialog or not main_dialog.visible then return end
    local table_view_selection = main_dialog["flow_production_pane"]["table_production_titlebar"]
      ["table_production_titlebar_view_selection"]
    if not (main_dialog["flow_production_pane"] and main_dialog["flow_production_pane"]["table_production_titlebar"]
     and table_view_selection) then return end

    -- Only change the view_state if it exists and is visible
    if ui_state.view_state ~= nil and table_view_selection.visible then
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
end

-- Moves on the selection until it is on an enabled state (at least 1 view needs to be enabled)
function correct_view_state(view_state, id_to_select)
    while true do
        view = view_state[id_to_select]
        if view.enabled then
            view.selected = true
            view_state.selected_view_id = id_to_select
            break
        else
            id_to_select = (id_to_select % #view_state) + 1
        end
    end
end
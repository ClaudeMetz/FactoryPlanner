-- Creates the production pane that displays 
function add_production_pane_to(main_dialog)
    local flow = main_dialog.add{type="flow", name="flow_production_pane", direction="vertical"}

    -- Production titlebar
    local table_titlebar = flow.add{type="table", name="table_production_titlebar", column_count=5}
    table_titlebar.style.top_margin = 10
    table_titlebar.style.bottom_margin = 4

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
    scroll_pane.style.minimal_height = 630
    scroll_pane.style.left_margin = 4
    scroll_pane.style.extra_left_margin_when_activated = -4
    scroll_pane.style.extra_top_margin_when_activated = -4
    scroll_pane.style.horizontally_stretchable = true
    scroll_pane.style.vertically_stretchable = true

    local column_count = 7
    local table = scroll_pane.add{type="table", name="table_production_pane",  column_count=column_count}
    table.style = "table_with_selection"
    table.style.top_margin = 0
    table.style.left_margin = 6
    for i=1, column_count do
        if i < 5 then table.style.column_alignments[i] = "middle-center"
        else table.style.column_alignments[i] = "middle-left" end
    end

    refresh_production_pane(game.get_player(main_dialog.player_index))
end

-- Refreshes the production pane (titlebar + table)
function refresh_production_pane(player)
    local flow_production = player.gui.center["fp_frame_main_dialog"]["flow_production_pane"]
     -- Cuts function short if the production pane hasn't been initialized yet
    if not flow_production then return end

    local table_titlebar = flow_production["table_production_titlebar"]
    table_titlebar.visible = false

    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    
    -- Configure Floor labels and buttons
    if subfactory ~= nil and subfactory.valid then
        table_titlebar.visible = true

        local floor = player_table.context.floor
        if floor.Line.count > 0 then
            table_titlebar["label_production_titlebar_level"].caption = {"", {"label.level"}, " ", floor.level, "  "}
        end
        table_titlebar["table_production_titlebar_navigation"].visible = (floor.level > 1)

        -- Configure view buttons
        local table_view = table_titlebar["table_production_titlebar_view_selection"]
        table_view.visible = (floor.Line.count > 0)
        
        if player_table.view_state == nil then ui_util.view_state.refresh(player_table) end
        for _, view in ipairs(player_table.view_state) do
            local button = table_view["fp_button_production_titlebar_view_" .. view.name]
            if view.name == "belts_or_lanes" then
                local flow = button["flow_belts_or_lanes"]
                flow["label_belts_or_lanes"].caption = view.caption
                flow["sprite_belts_or_lanes"].sprite = "entity/" .. player_table.preferred_belt_name
            else
                button.caption = view.caption
            end
            button.enabled = view.enabled
            button.style = view.selected and "fp_view_selection_button_pressed" or "fp_view_selection_button"
        end
    end

    refresh_production_table(player)
end


-- Handles a click on a button that changes the viewed floor of a subfactory
function handle_floor_change_click(player, destination)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local floor = player_table.context.floor

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
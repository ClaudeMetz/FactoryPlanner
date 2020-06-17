titlebar = {}

-- ** TOP LEVEL **
-- Creates the titlebar including name and exit-button
function titlebar.add_to(main_dialog)
    local flow_titlebar = main_dialog.add{type="flow", name="flow_titlebar", direction="horizontal"}

    -- Title
    local label_title = flow_titlebar.add{type="label", name="label_titlebar_name", caption=" Factory Planner"}
    label_title.style.font = "fp-font-bold-26p"

    -- Hint
    local label_hint = flow_titlebar.add{type="label", name="label_titlebar_hint"}
    label_hint.style.font = "fp-font-semibold-18p"
    label_hint.style.top_margin = 6
    label_hint.style.left_margin = 14

    -- Spacer
    local flow_spacer = flow_titlebar.add{type="flow", name="flow_titlebar_spacer", direction="horizontal"}
    flow_spacer.style.horizontally_stretchable = true

    -- Drag handle
    local handle = flow_titlebar.add{type="empty-widget", name="empty-widget_titlebar_space", style="draggable_space"}
    handle.style.height = 34
    handle.style.width = 180
    handle.style.top_margin = 4
    handle.drag_target = main_dialog

    -- Buttonbar
    local flow_buttonbar = flow_titlebar.add{type="flow", name="flow_titlebar_buttonbar", direction="horizontal"}
    flow_buttonbar.style.top_margin = 4

    flow_buttonbar.add{type="button", name="fp_button_titlebar_tutorial", caption={"fp.tutorial"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}
    flow_buttonbar.add{type="button", name="fp_button_titlebar_preferences", caption={"fp.preferences"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}

    local button_pause = flow_buttonbar.add{type="sprite-button", name="fp_button_titlebar_pause",
      sprite="utility/pause", tooltip={"fp.pause_on_interface"}, mouse_button_filter={"left"}}
    button_pause.style.left_margin = 4

    flow_buttonbar.add{type="sprite-button", name="fp_button_titlebar_exit", sprite="utility/close_fat",
      tooltip={"fp.close_interface"}, style="fp_button_titlebar_square", mouse_button_filter={"left"}}


    titlebar.refresh(game.get_player(main_dialog.player_index))
end

-- Refreshes the pause_on_interface-button
function titlebar.refresh(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    local button_pause = main_dialog["flow_titlebar"]["flow_titlebar_buttonbar"]["fp_button_titlebar_pause"]
    button_pause.enabled = (not game.is_multiplayer())
    button_pause.style = (get_preferences(player).pause_on_interface) and
      "fp_button_titlebar_square_selected" or "fp_button_titlebar_square"
end


-- Handles a click on the pause_on_interface button
function titlebar.handle_pause_button_click(player, button)
    if not game.is_multiplayer() then
        local preferences = get_preferences(player)
        preferences.pause_on_interface = not preferences.pause_on_interface

        button.style = (preferences.pause_on_interface) and
          "fp_button_titlebar_square_selected" or "fp_button_titlebar_square"

        local main_dialog = player.gui.screen["fp_frame_main_dialog"]
        set_pause_state(player, main_dialog)
    end
end
-- Handles populating the chooser dialog
function open_chooser_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local modal_data = get_ui_state(player).modal_data
    flow_modal_dialog.parent.caption = {"", {"label.choose"}, " ", modal_data.title}
    flow_modal_dialog.add{type="label", name="label_chooser_text", caption=modal_data.text}

    local table_chooser = flow_modal_dialog.add{type="table", name="table_chooser_elements", column_count=8}
    table_chooser.style.top_padding = 6
    table_chooser.style.bottom_padding = 10
    table_chooser.style.left_padding = 6

    -- This is the function that will populate the chooser dialog, requesting as many blank chooser buttons as needed
    -- using the 'generate_blank_chooser_button'-function below
    _G["generate_chooser_" .. modal_data.reciever_name .. "_buttons"](player)
end

-- Generates a blank chooser button for the calling function to adjust to it's needs
function generate_blank_chooser_button(player, name)
    local table_chooser = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["table_chooser_elements"]
    return table_chooser.add{type="sprite-button", name="fp_sprite-button_chooser_element_" .. name,
             style="fp_button_icon_large_recipe", mouse_button_filter={"left"}}
end

-- Handles click on an element presented by the chooser
function handle_chooser_element_click(player, element_name)
    _G["apply_chooser_" .. get_ui_state(player).modal_data.reciever_name .. "_choice"](player, element_name)
    exit_modal_dialog(player, "cancel", {})
end
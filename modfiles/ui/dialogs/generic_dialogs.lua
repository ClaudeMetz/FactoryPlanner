-- This file contains general-purpose dialogs that are generic and used in several places

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
function handle_chooser_element_click(player, element_id)
    _G["apply_chooser_" .. get_ui_state(player).modal_data.reciever_name .. "_choice"](player, element_id)
    exit_modal_dialog(player, "cancel", {})
end

-- Handles populating the setter dialog
function open_setter_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local modal_data = get_ui_state(player).modal_data
    flow_modal_dialog.parent.caption = {"", {"label.set"}, " ", modal_data.title}
    flow_modal_dialog.add{type="label", name="label_setter_text", caption=modal_data.text}

    if modal_data.type == "numeric" then
        local table_setter = flow_modal_dialog.add{type="table", name="table_setter", column_count=2}
        table_setter.style.top_padding = 6
        table_setter.style.bottom_padding = 10
        table_setter.style.left_padding = 10
        table_setter.style.horizontal_spacing = 16

        table_setter.add{type="label", name="label_setter_caption", caption=modal_data.caption}

        local textfield_setter = table_setter.add{type="textfield", name="fp_textfield_setter_numeric",
          text=modal_data.value}
        ui_util.setup_numeric_textfield(textfield_setter, true, false)
        textfield_setter.style.width = 60
        textfield_setter.focus()
    end
end

-- Handles closing of the setter dialog
function close_setter_dialog(flow_modal_dialog, action, data)
    if action == "submit" then
        local player = game.get_player(flow_modal_dialog.player_index)
        local object = get_ui_state(player).modal_data.object
        _G["apply_setter_" .. get_ui_state(player).modal_data.reciever_name .. "_choice"](player, object, data.number)
    end
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_setter_condition_instructions()
    return {
        data = {
            number = (function(flow_modal_dialog)
                return tonumber(flow_modal_dialog["table_setter"]["fp_textfield_setter_numeric"].text) end)
        },
        conditions = {
        }
    }
end
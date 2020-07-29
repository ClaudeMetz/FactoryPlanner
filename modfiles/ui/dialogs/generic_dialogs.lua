-- This file contains general-purpose dialogs that are generic and used in several places
chooser_dialog = {}
options_dialog = {}

-- ** CHOOSER **
-- ** TOP LEVEL **
-- Handles populating the chooser dialog
function chooser_dialog.open(player, flow_modal_dialog, modal_data)
    flow_modal_dialog.parent.caption = {"", {"fp.choose"}, " ", modal_data.title}
    flow_modal_dialog.add{type="label", name="label_chooser_text", caption=modal_data.text}

    local table_chooser = flow_modal_dialog.add{type="table", name="table_chooser_elements", column_count=8}
    table_chooser.style.padding = {6, 4, 10, 6}

    -- This is the function that will populate the chooser dialog, requesting as many blank chooser buttons as needed
    -- using the 'chooser_dialog.generate_blank_button'-function below
    modal_data.button_generator(player)
end

-- Generates a blank chooser button for the calling function to adjust to it's needs
function chooser_dialog.generate_blank_button(player, name)
    local table_chooser = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["table_chooser_elements"]
    return table_chooser.add{type="sprite-button", name="fp_sprite-button_chooser_element_" .. name,
             style="fp_button_icon_large_recipe", mouse_button_filter={"left"}}
end

-- Handles click on an element presented by the chooser
function chooser_dialog.handle_element_click(player, element_id)
    get_ui_state(player).modal_data.click_handler(player, element_id)
    modal_dialog.exit(player, "cancel", {})
    main_dialog.refresh(player)
end



-- ** OPTIONS **
-- ** LOCAL UTIL **
local option_creators = {}
function option_creators.numeric(table, field)
    local textfield = table.add{type="textfield", name="textfield_option_numeric", text=field.value}
    textfield.style.left_margin = 1
    textfield.style.width = (field.width or 75)
    ui_util.setup_numeric_textfield(textfield, true, false)
    if field.focus then ui_util.select_all(textfield) end

    local caption = (field.tooltip ~= nil) and {"", field.caption, " [img=info]"} or field.caption
    local label = table.add{type="label", name="label_option_caption", caption=caption, tooltip=field.tooltip}
    label.style.font = "fp-font-15p"
    label.style.left_padding = 2
end

function option_creators.on_off_switch(table, field)
    ui_util.switch.add_on_off(table, field.name, field.value, field.caption, field.tooltip)
end


-- ** TOP LEVEL **
-- Handles populating the options dialog
function options_dialog.open(_, flow_modal_dialog, modal_data)
    flow_modal_dialog.parent.caption = {"", {"fp.set"}, " ", modal_data.title}
    flow_modal_dialog.add{type="label", name="label_options_text", caption=modal_data.text}

    local flow_options = flow_modal_dialog.add{type="flow", name="flow_options", direction="vertical"}
    flow_options.style.padding = {6, 4, 10, 10}
    flow_options.style.vertical_spacing = 10

    for _, field in ipairs(modal_data.fields) do
        local table_option = flow_options.add{type="table", name="table_option_" .. field.name, column_count=2}
        table_option.style.horizontal_spacing = 12

        option_creators[field.type](table_option, field)
    end
end

-- Handles closing of the options dialog
function options_dialog.close(player, action, data)
    if action == "submit" then
        local modal_data = get_ui_state(player).modal_data
        modal_data.submission_handler(player, modal_data.object, data)
        main_dialog.refresh(player)
    end
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function options_dialog.condition_instructions(modal_data)
    local instructions = {
        data = {},
        conditions = nil
    }

    for _, field in ipairs(modal_data.fields) do
        if field.type == "numeric" then
            instructions.data[field.name] = (function(flow_modal_dialog) return tonumber(flow_modal_dialog
              ["flow_options"]["table_option_" .. field.name]["textfield_option_numeric"].text) end)

        elseif field.type == "on_off_switch" then
            instructions.data[field.name] = (function(flow_modal_dialog) return ui_util.switch.get_state
              (flow_modal_dialog["flow_options"]["table_option_" .. field.name], field.name, true) end)
        end
    end

    return instructions
end
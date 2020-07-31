-- This file contains general-purpose dialogs that are generic and used in several places
chooser_dialog = {}
options_dialog = {}

-- ** CHOOSER **
local function add_chooser_button(ui_elements, definition)
    local element_name = "fp_sprite-button_chooser_element_" .. definition.element_id
    local style = (definition.selected) and "flib_slot_button_green" or "flib_slot_button_default"

    local first_line = (definition.selected) and {"fp.annotated_title", definition.localised_name, {"fp.selected"}}
      or definition.localised_name
    local tooltip = {"", first_line, "\n", definition.amount_line, "\n\n", definition.tooltip_appendage}

    ui_elements.choices_table.add{type="sprite-button", name=element_name, style=style, tooltip=tooltip,
      sprite=definition.sprite, number=definition.button_number, mouse_button_filter={"left"}}
end

local function handler_chooser_button_click(player, element)
    local element_id = string.gsub(element.name, "fp_sprite%-button_chooser_element_", "")
    data_util.get("modal_data", player).click_handler(player, element_id)
    modal_dialog.exit(player, "cancel", {})
    main_dialog.refresh(player)
end


chooser_dialog.dialog_settings = (function(modal_data) return {
    caption = {"fp.two_word_title", {"fp.choose"}, modal_data.title}
} end)

chooser_dialog.events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_chooser_element_[0-9_]+$",
            handler = (function(player, element)
                handler_chooser_button_click(player, element)
            end)
        }
    }
}

-- Handles populating the chooser dialog
function chooser_dialog.open(_, _, modal_data)
    local ui_elements = modal_data.ui_elements

    local content_frame = ui_elements.flow_modal_dialog.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}
    content_frame.add{type="label", caption=modal_data.text}

    local frame_choices = content_frame.add{type="frame", direction="horizontal", style="deep_frame_in_shallow_frame"}
    frame_choices.style.margin = {8, 0, 0, 4}
    ui_elements.choices_table = frame_choices.add{type="table", column_count=8, style="filter_slot_table"}

    for _, definition in ipairs(modal_data.button_definitions) do
        add_chooser_button(ui_elements, definition)
    end
end


-- ** OPTIONS **
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
    ui_util.switch.add_on_off(table, field.name, field.value, field.caption, field.tooltip, false)
end


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
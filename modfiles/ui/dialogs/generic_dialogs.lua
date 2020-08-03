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
            handler = (function(player, element, _)
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

    local frame_choices = content_frame.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    frame_choices.style.margin = {10, 0, 4, 0}
    ui_elements.choices_table = frame_choices.add{type="table", column_count=8, style="filter_slot_table"}

    for _, definition in ipairs(modal_data.button_definitions) do
        add_chooser_button(ui_elements, definition)
    end
end



-- ** OPTIONS **
local option_creators, option_extractors = {}, {}

function option_creators.numeric_textfield(table, field, ui_elements)
    local textfield = table.add{type="textfield", name="fp_textfield_options_numeric_" .. field.name, text=field.text}
    textfield.style.width = (field.width or 75)
    ui_util.setup_numeric_textfield(textfield, true, false)
    if field.focus then ui_util.select_all(textfield) end
    ui_elements["numeric_textfield_" .. field.name] = textfield
end

function option_extractors.numeric_textfield(element)
    return tonumber(element.text)
end


function option_creators.on_off_switch(table, field, ui_elements)
    local state = ui_util.switch.convert_to_state(field.state)
    local switch = table.add{type="switch", name="fp_switch_on_off_options_" .. field.name, switch_state=state,
      left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}
      ui_elements["on_off_switch_" .. field.name] = switch
end

function option_extractors.on_off_switch(element)
    return ui_util.switch.convert_to_boolean(element.switch_state)
end


options_dialog.dialog_settings = (function(modal_data) return {
    caption = {"fp.two_word_title", {"fp.set"}, modal_data.title}
} end)

function options_dialog.open(_, _, modal_data)
    local ui_elements = modal_data.ui_elements

    local content_frame = ui_elements.flow_modal_dialog.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}
    content_frame.add{type="label", caption=modal_data.text}

    local table_options = content_frame.add{type="table", column_count=2}
    table_options.style.margin = {12, 0, 4, 2}
    table_options.style.horizontal_spacing = 24
    table_options.style.vertical_spacing = 16

    for _, field in ipairs(modal_data.fields) do
        local caption = (field.tooltip) and {"fp.info_label", field.caption} or field.caption
        local label = table_options.add{type="label", caption=caption, tooltip=field.tooltip}
        label.style.font = "heading-3"

        option_creators[field.type](table_options, field, ui_elements)
    end
end

function options_dialog.close(player, action, _)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local modal_data = ui_state.modal_data

        local options_data = {}
        for _, field in pairs(modal_data.fields) do
            local element = modal_data.ui_elements[field.type .. "_" .. field.name]
            options_data[field.name] = option_extractors[field.type](element)
        end

        modal_data.submission_handler(modal_data.object, options_data)
        calculation.update(player, ui_state.context.subfactory, true)
    end
end
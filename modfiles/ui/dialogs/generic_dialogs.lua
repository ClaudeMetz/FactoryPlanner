-- This file contains general-purpose dialogs that are generic and used in several places
-- Note: This system seems to have a problem, as references to functions stored in global
-- break when reloading the game. In that case, just close the dialog without changes
chooser_dialog = {}
options_dialog = {}

-- ** CHOOSER **
local function add_chooser_button(modal_elements, definition)
    local element_name = "fp_sprite-button_chooser_element_" .. definition.element_id
    local style, indication = "flib_slot_button_default", ""

    if definition.selected then
        style = "flib_slot_button_green"
        indication = {"fp.indication", {"fp.selected"}}
    elseif definition.preferred then
        style = "flib_slot_button_pink"
        indication = {"fp.indication", {"fp.preferred"}}
    end

    local first_line = {"fp.two_word_title", definition.localised_name, indication}
    local tooltip = {"", first_line, "\n", definition.amount_line, "\n\n", definition.tooltip_appendage}

    modal_elements.choices_table.add{type="sprite-button", name=element_name, style=style, tooltip=tooltip,
      sprite=definition.sprite, number=definition.button_number, mouse_button_filter={"left"}}
end

local function handler_chooser_button_click(player, element, metadata)
    local element_id = string.gsub(element.name, "fp_sprite%-button_chooser_element_", "")
    local click_handler = data_util.get("modal_data", player).click_handler

    -- If no click handler is present, just abort mission
    if click_handler then click_handler(player, element_id, metadata) end

    modal_dialog.exit(player, "cancel")
end

chooser_dialog.dialog_settings = (function(modal_data)
    local info_tag = (modal_data.text_tooltip) and "[img=info]" or ""
    return {
        caption = {"fp.two_word_title", {"fp.choose"}, modal_data.title},
        subheader_text = {"fp.chooser_text", modal_data.text, info_tag},
        subheader_tooltip = (modal_data.text_tooltip or ""),
        create_content_frame = true
    }
end)

-- Handles populating the chooser dialog
function chooser_dialog.open(_, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local frame_choices = content_frame.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    modal_elements.choices_table = frame_choices.add{type="table", column_count=8, style="filter_slot_table"}

    for _, definition in ipairs(modal_data.button_definitions) do
        add_chooser_button(modal_elements, definition)
    end
end

chooser_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_chooser_element_[0-9_]+$",
            timeout = 20,
            handler = handler_chooser_button_click
        }
    }
}


-- ** OPTIONS **
-- ** LOCAL UTIL **
local function call_change_handler(player, element)
    local modal_data = data_util.get("modal_data", player)
    local change_handler = modal_data.field_handlers[element.name]
    if change_handler then change_handler(modal_data, element) end
end

-- ** ELEMENTS **
options_dialog.gui_events = {}
local elements = {}

-- ** TEXTFIELD **
elements.textfield = {prefix = "fp_textfield_options_"}

function elements.textfield.create(table, field, modal_elements)
    local element_name = elements.textfield.prefix .. field.name
    local textfield = table.add{type="textfield", name=element_name, text=field.text}
    textfield.style.width = (field.width or 180)
    if field.focus then ui_util.select_all(textfield) end

    modal_elements[element_name] = textfield
    return element_name
end

function elements.textfield.read(textfield)
    return textfield.text
end

-- ** NUMERIC TEXTFIELD **
elements.numeric_textfield = {prefix = "fp_textfield_options_numberic_"}

function elements.numeric_textfield.create(table, field, modal_elements)
    local element_name = elements.numeric_textfield.prefix .. field.name
    local textfield = table.add{type="textfield", name=element_name, text=tostring(field.text or "")}
    textfield.style.width = (field.width or 75)
    ui_util.setup_numeric_textfield(textfield, true, false)
    if field.focus then ui_util.select_all(textfield) end

    modal_elements[element_name] = textfield
    return element_name
end

function elements.numeric_textfield.read(textfield)
    return tonumber(textfield.text)
end

-- ** TEXTFIELD EVENT **
options_dialog.gui_events.on_gui_text_changed = {
    {
        pattern = "^fp_textfield_options_[a-z_]+$",
        handler = call_change_handler
    }
}

-- ** ON OFF SWITCH **
elements.on_off_switch = {prefix = "fp_switch_on_off_options_"}

options_dialog.gui_events.on_gui_switch_state_changed = {
    {
        pattern = "^" .. elements.on_off_switch.prefix .. "[a-z_]+$",
        handler = call_change_handler
    }
}

function elements.on_off_switch.create(table, field, modal_elements)
    local element_name = elements.on_off_switch.prefix .. field.name
    local state = ui_util.switch.convert_to_state(field.state)
    local switch = table.add{type="switch", name=element_name, switch_state=state,
      left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}

    modal_elements[element_name] = switch
    return element_name
end

function elements.on_off_switch.read(switch)
    return ui_util.switch.convert_to_boolean(switch.switch_state)
end

-- ** CHOOSE ELEM BUTTON **
elements.choose_elem_button = {prefix = "fp_choose_elem_button_options_"}

options_dialog.gui_events.on_gui_elem_changed = {
    {
        pattern = "^" .. elements.choose_elem_button.prefix .. "[a-z_]+$",
        handler = call_change_handler
    }
}

function elements.choose_elem_button.create(table, field, modal_elements)
    local element_name = elements.choose_elem_button.prefix .. field.name
    local choose_elem_button = table.add{type="choose-elem-button", name=element_name,
      elem_type=field.elem_type, style="fp_sprite-button_inset"}
    choose_elem_button.elem_value = field.elem_value

    modal_elements[element_name] = choose_elem_button
    return element_name
end

function elements.choose_elem_button.read(choose_elem_button)
    return choose_elem_button.elem_value
end


options_dialog.dialog_settings = (function(modal_data) return {
    caption = modal_data.title,
    subheader_text = modal_data.text,
    create_content_frame = true,
    show_submit_button = true,
    show_delete_button = modal_data.allow_deletion
} end)

function options_dialog.open(_, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local table_options = content_frame.add{type="table", column_count=2}
    table_options.style.margin = {0, 12, 8, 2}
    table_options.style.horizontal_spacing = 24
    table_options.style.vertical_spacing = 16

    modal_data.field_handlers = {}
    for _, field in ipairs(modal_data.fields) do
        local caption = (field.tooltip) and {"fp.info_label", field.caption} or field.caption
        local label = table_options.add{type="label", caption=caption, tooltip=field.tooltip}
        label.style.font = "heading-3"

        local element_name = elements[field.type].create(table_options, field, modal_elements)
        modal_data.field_handlers[element_name] = field.change_handler
    end

    -- Call all the change handlers once to set the initial state correctly
    for element_name, change_handler in pairs(modal_data.field_handlers) do
        change_handler(modal_data, modal_elements[element_name])
    end
end

function options_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local modal_elements = modal_data.modal_elements

    local options_data = {}
    for _, field in pairs(modal_data.fields) do
        local element = modal_elements[elements[field.type].prefix .. field.name]
        options_data[field.name] = elements[field.type].read(element)
    end

    local submission_handler = modal_data.submission_handler
    -- If no submission handler is present, just abort mission
    if submission_handler then submission_handler(player, options_data, action) end
end
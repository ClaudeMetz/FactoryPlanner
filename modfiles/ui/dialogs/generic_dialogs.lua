-- This file contains general-purpose dialogs that are generic and used in several places
-- Note: This system seems to have a problem, as references to functions stored in global
-- break when reloading the game. In that case, just close the dialog without changes
chooser_dialog = {}
options_dialog = {}

-- ** CHOOSER **
local function add_chooser_button(modal_elements, definition)
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

    modal_elements.choices_table.add{type="sprite-button", style=style, tooltip=tooltip,
      tags={on_gui_click="make_chooser_choice", element_id=definition.element_id},
      sprite=definition.sprite, number=definition.button_number, mouse_button_filter={"left"}}
end

local function handler_chooser_button_click(player, tags, metadata)
    local click_handler = data_util.get("modal_data", player).click_handler
    -- If no click handler is present, just abort mission
    if click_handler then click_handler(player, tags.element_id, metadata) end

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
            name = "make_chooser_choice",  -- great naming right there
            timeout = 20,
            handler = handler_chooser_button_click
        }
    }
}


-- ** OPTIONS **
-- ** LOCAL UTIL **
local function call_change_handler(player, tags, metadata)
    local modal_data = data_util.get("modal_data", player)
    local change_handler = modal_data.field_handlers[tags.field_name]
    if change_handler then change_handler(modal_data, metadata) end
end

-- ** ELEMENTS **
options_dialog.gui_events = {}
local elements = {}

-- ** TEXTFIELD **
elements.textfield = {}

function elements.textfield.create(table, field, modal_elements)
    local textfield = table.add{type="textfield", text=field.text,
      tags={on_gui_text_changed="change_option", field_name=field.name}}
    textfield.style.width = (field.width or 180)
    if field.focus then ui_util.select_all(textfield) end

    modal_elements[field.name] = textfield
end

function elements.textfield.read(textfield)
    return textfield.text
end

-- ** NUMERIC TEXTFIELD **
elements.numeric_textfield = {}

function elements.numeric_textfield.create(table, field, modal_elements)
    local textfield = table.add{type="textfield", text=tostring(field.text or ""),
      tags={on_gui_text_changed="change_option", field_name=field.name}}
    textfield.style.width = (field.width or 75)
    ui_util.setup_numeric_textfield(textfield, true, false)
    if field.focus then ui_util.select_all(textfield) end

    modal_elements[field.name] = textfield
end

function elements.numeric_textfield.read(textfield)
    return tonumber(textfield.text)
end

-- ** TEXTFIELD EVENT **
options_dialog.gui_events.on_gui_text_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

-- ** ON OFF SWITCH **
elements.on_off_switch = {}

options_dialog.gui_events.on_gui_switch_state_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

function elements.on_off_switch.create(table, field, modal_elements)
    local state = ui_util.switch.convert_to_state(field.state)
    local switch = table.add{type="switch", switch_state=state,
      tags={on_gui_switch_state_changed="change_option", field_name=field.name},
      left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}

    modal_elements[field.name] = switch
end

function elements.on_off_switch.read(switch)
    return ui_util.switch.convert_to_boolean(switch.switch_state)
end

-- ** CHOOSE ELEM BUTTON **
elements.choose_elem_button = {}

options_dialog.gui_events.on_gui_elem_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

function elements.choose_elem_button.create(table, field, modal_elements)
    local choose_elem_button = table.add{type="choose-elem-button",
      tags={on_gui_elem_changed="change_option", field_name=field.name},
      elem_type=field.elem_type, style="fp_sprite-button_inset"}
    choose_elem_button.elem_value = field.elem_value

    modal_elements[field.name] = choose_elem_button
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

        elements[field.type].create(table_options, field, modal_elements)
        modal_data.field_handlers[field.name] = field.change_handler
    end

    -- Call all the change handlers once to set the initial state correctly
    for field_name, change_handler in pairs(modal_data.field_handlers) do
        change_handler(modal_data, modal_elements[field_name])
    end
end

function options_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)

    local options_data = {}
    for _, field in pairs(modal_data.fields) do
        local element = modal_data.modal_elements[field.name]
        options_data[field.name] = elements[field.type].read(element)
    end

    local submission_handler = modal_data.submission_handler
    -- If no submission handler is present, just abort mission
    if submission_handler then submission_handler(player, options_data, action) end
end
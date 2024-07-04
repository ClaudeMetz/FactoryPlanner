-- This file contains general-purpose dialogs that are generic and used in several places
-- Note: This system seems to have a problem, as references to functions stored in global
-- break when reloading the game. In that case, just close the dialog without changes

-- ** CHOOSER **
local function add_chooser_button(modal_elements, definition)
    local style, note = "flib_slot_button_default", nil

    if definition.selected then
        style = "flib_slot_button_green"
        note = {"fp.selected"}
    elseif definition.preferred then
        style = "flib_slot_button_pink"
        note = {"fp.preferred"}
    end

    local first_line = (note == nil) and {"fp.tt_title", definition.localised_name}
        or {"fp.tt_title_with_note", definition.localised_name, note}
    local tooltip = {"", first_line, "\n", definition.amount_line, "\n\n", definition.tooltip_appendage}

    modal_elements.choices_table.add{type="sprite-button", style=style, tooltip=tooltip,
        tags={mod="fp", on_gui_click="make_chooser_choice", element_id=definition.element_id},
        sprite=definition.sprite, number=definition.button_number, mouse_button_filter={"left"}}
end

local function handler_chooser_button_click(player, tags, event)
    local handler_name = util.globals.modal_data(player).click_handler_name
    GLOBAL_HANDLERS[handler_name](player, tags.element_id, event)

    util.raise.close_dialog(player, "cancel")
end

-- Handles populating the chooser dialog
local function open_chooser_dialog(_, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local frame_choices = content_frame.add{type="frame", direction="horizontal", style="slot_button_deep_frame"}
    modal_elements.choices_table = frame_choices.add{type="table", column_count=8, style="filter_slot_table"}

    for _, definition in ipairs(modal_data.button_definitions) do
        add_chooser_button(modal_elements, definition)
    end
end


-- ** EVENTS **
local chooser_listeners = {}

chooser_listeners.gui = {
    on_gui_click = {
        {
            name = "make_chooser_choice",  -- great naming right there
            timeout = 20,
            handler = handler_chooser_button_click
        }
    }
}

chooser_listeners.dialog = {
    dialog = "chooser",
    metadata = (function(modal_data)
        local info_tag = (modal_data.text_tooltip) and "[img=info]" or ""
        return {
            caption = {"", {"fp.choose"}, " ", modal_data.title},
            subheader_text = {"", modal_data.text, " ", info_tag},
            subheader_tooltip = (modal_data.text_tooltip or ""),
            create_content_frame = true
        }
    end),
    open = open_chooser_dialog
}


-- ** OPTIONS **
local options_listeners = {}

-- ** LOCAL UTIL **
local function call_change_handler(player, tags, event)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]
    local handler_name = modal_data.field_handlers[tags.field_name]
    if handler_name then GLOBAL_HANDLERS[handler_name](modal_data, event) end
end

-- ** ELEMENTS **
options_listeners.gui = {}
local elements = {}

-- ** TEXTFIELD **
elements.textfield = {}

function elements.textfield.create(table, field, modal_elements)
    local textfield = table.add{type="textfield", text=field.text,
        tags={mod="fp", on_gui_text_changed="change_option", field_name=field.name}}
    textfield.style.width = (field.width or 180)
    if field.focus then util.gui.select_all(textfield) end

    modal_elements[field.name] = textfield
end

function elements.textfield.read(textfield)
    return textfield.text
end

-- ** NUMERIC TEXTFIELD **
elements.numeric_textfield = {}

function elements.numeric_textfield.create(table, field, modal_elements)
    local textfield = table.add{type="textfield", text=tostring(field.text or ""),
        tags={mod="fp", on_gui_text_changed="change_option", field_name=field.name}}
    textfield.style.width = (field.width or 75)
    util.gui.setup_numeric_textfield(textfield, true, false)
    if field.focus then util.gui.select_all(textfield) end

    modal_elements[field.name] = textfield
end

function elements.numeric_textfield.read(textfield)
    return tonumber(textfield.text)
end

-- ** TEXTFIELD EVENT **
options_listeners.gui.on_gui_text_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

-- ** ON OFF SWITCH **
elements.on_off_switch = {}

options_listeners.gui.on_gui_switch_state_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

function elements.on_off_switch.create(table, field, modal_elements)
    local state = util.gui.switch.convert_to_state(field.state)
    local switch = table.add{type="switch", switch_state=state,
        tags={mod="fp", on_gui_switch_state_changed="change_option", field_name=field.name},
        left_label_caption={"fp.on"}, right_label_caption={"fp.off"}}

    modal_elements[field.name] = switch
end

function elements.on_off_switch.read(switch)
    return util.gui.switch.convert_to_boolean(switch.switch_state)
end

-- ** CHOOSE ELEM BUTTON **
elements.choose_elem_button = {}

options_listeners.gui.on_gui_elem_changed = {
    {
        name = "change_option",
        handler = call_change_handler
    }
}

function elements.choose_elem_button.create(table, field, modal_elements)
    local choose_elem_button = table.add{type="choose-elem-button",
        tags={mod="fp", on_gui_elem_changed="change_option", field_name=field.name},
        elem_type=field.elem_type, style="fp_sprite-button_inset"}
    choose_elem_button.elem_value = field.elem_value

    modal_elements[field.name] = choose_elem_button
end

function elements.choose_elem_button.read(choose_elem_button)
    return choose_elem_button.elem_value
end


local function open_options_dialog(_, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local table_options = content_frame.add{type="table", column_count=2}
    table_options.style.margin = {0, 12, 8, 2}
    table_options.style.horizontal_spacing = 24
    table_options.style.vertical_spacing = 16

    modal_data.field_handlers = {}
    for _, field in ipairs(modal_data.fields) do
        local caption = (field.tooltip) and {"fp.info_label", field.caption} or field.caption
        table_options.add{type="label", caption=caption, tooltip=field.tooltip, style="semibold_label"}

        elements[field.type].create(table_options, field, modal_elements)
        modal_data.field_handlers[field.name] = field.change_handler_name
    end

    -- Call all the change handlers once to set the initial state correctly
    for field_name, handler_name in pairs(modal_data.field_handlers) do
        GLOBAL_HANDLERS[handler_name](modal_data, modal_elements[field_name])
    end
end

local function close_options_dialog(player, action)
    local modal_data = util.globals.modal_data(player)  --[[@as table]]

    local options_data = {}
    for _, field in pairs(modal_data.fields) do
        local element = modal_data.modal_elements[field.name]
        options_data[field.name] = elements[field.type].read(element)
    end

    local handler_name = modal_data.submission_handler_name
    GLOBAL_HANDLERS[handler_name](player, options_data, action)
end

options_listeners.dialog = {
    dialog = "options",
    metadata = (function(modal_data) return {
        caption = modal_data.title,
        subheader_text = modal_data.text,
        create_content_frame = true,
        show_submit_button = true,
        show_delete_button = modal_data.allow_deletion
    } end),
    open = open_options_dialog,
    close = close_options_dialog
}

return { chooser_listeners, options_listeners }

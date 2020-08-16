import_dialog = {}
export_dialog = {}
porter_dialog = {}  -- table containing functionality shared between both dialogs

-- ** LOCAL UTIL **
local function set_tool_button_state(button, dialog_type, enabled)
    button.enabled = enabled
    button.sprite = (enabled) and ("utility/" .. dialog_type) or ("fp_sprite_" .. dialog_type .. "_light")
end

local function set_dialog_submit_button(ui_elements, enabled, action_to_take)
    local message = (not enabled) and {"fp.importer_issue_" .. action_to_take} or nil
    modal_dialog.set_submit_button_state(ui_elements, enabled, message)
end

-- Sets the state of either the export_subfactories- or dialog_submit-button
local function set_relevant_submit_button(ui_elements, dialog_type, enabled)
    if dialog_type == "export" then
        set_tool_button_state(ui_elements.export_button, dialog_type, enabled)

    else -- dialog_type == "import"
        set_dialog_submit_button(ui_elements, enabled, "select_subfactory")
    end
end


-- Sets the slave checkboxes after the master one has been clicked
local function set_all_checkboxes(player, checkbox_state)
    local ui_state = data_util.get("ui_state", player)
    local ui_elements = ui_state.modal_data.ui_elements

    for _, table_row in pairs(ui_elements.table_rows) do
        if table_row.checkbox.enabled then table_row.checkbox.state = checkbox_state end
    end

    set_relevant_submit_button(ui_elements, ui_state.modal_dialog_type, checkbox_state)
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
local function adjust_after_checkbox_click(player)
    local ui_state = data_util.get("ui_state", player)
    local ui_elements = ui_state.modal_data.ui_elements

    local checked_element_count, unchecked_element_count = 0, 0
    for _, table_row in pairs(ui_elements.table_rows) do
        if table_row.checkbox.state == true then checked_element_count = checked_element_count + 1
        elseif table_row.checkbox.enabled then unchecked_element_count = unchecked_element_count + 1 end
    end

    ui_elements.master_checkbox.state = (unchecked_element_count == 0)
    set_relevant_submit_button(ui_elements, ui_state.modal_dialog_type, (checked_element_count > 0))
end


-- Adds a flow containing a textfield and a button
local function add_textfield_and_button(ui_elements, dialog_type, button_first, button_enabled)
    local flow = ui_elements.content_frame.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"

    local function add_button()
        local button = flow.add{type="sprite-button", name="fp_button_porter_subfactory_" .. dialog_type,
          style="fp_sprite-button_tool_green", tooltip={"fp." .. dialog_type .. "_button_tooltip"},
          mouse_button_filter={"left"}}
        set_tool_button_state(button, dialog_type, button_enabled)
        ui_elements[dialog_type .. "_button"] = button
    end

    local function add_textfield()
        local textfield = flow.add{type="textfield", name="fp_textfield_porter_string_" .. dialog_type}
        ui_util.setup_textfield(textfield)
        textfield.style.width = 0  -- needs to be set to 0 so stretching works
        textfield.style.minimal_width = 280
        textfield.style.horizontally_stretchable = true

        if button_first then textfield.style.left_margin = 6
        else textfield.style.right_margin = 6 end

        ui_elements[dialog_type .. "_textfield"] = textfield
    end

    if button_first then add_button(); add_textfield()
    else add_textfield(); add_button() end
end


-- Initializes the subfactories table by adding it and its header
local function setup_subfactories_table(ui_elements, add_location)
    ui_elements.table_rows = {}

    local scroll_pane = ui_elements.content_frame.add{type="scroll-pane",
      style="fp_scroll_pane_inside_content_frame_bare"}
    scroll_pane.style.margin = 0
    scroll_pane.style.padding = 0
    scroll_pane.style.maximal_height = 450  -- I hate that I have to set this, seemingly
    ui_elements.subfactories_scroll_pane = scroll_pane

    local frame_subfactories = scroll_pane.add{type="frame", style="deep_frame_in_shallow_frame"}
    frame_subfactories.style.padding = {-2, 2, 3, 2}

    local table_columns = {
        [2] = {caption={"fp.pu_subfactory", 2}, alignment="left", margin={6, 130, 6, 4}},
        [3] = {caption={"fp.validity"}}
    }
    if add_location then table_columns[4] = {caption={"fp.location"}} end

    local table_subfactories = frame_subfactories.add{type="table", style="mods_table",
      column_count=(table_size(table_columns) + 1)}
    ui_elements.subfactories_table = table_subfactories

    -- Add master checkbox in any case
    local checkbox_master = table_subfactories.add{type="checkbox", name="fp_checkbox_porter_master", state=false}
    ui_elements.master_checkbox = checkbox_master

    for column_nr, table_column in pairs(table_columns) do
        table_subfactories.style.column_alignments[column_nr] = table_column.alignment or "center"

        local label_column = table_subfactories.add{type="label", caption=table_column.caption}
        label_column.style.font = "heading-3"
        label_column.style.margin = table_column.margin or {0, 4}
    end
end

-- Adds a row to the subfactories table
local function add_to_subfactories_table(ui_elements, subfactory, location_name, enable_checkbox)
    local table_subfactories = ui_elements.subfactories_table

    local identifier = (location_name or "tmp") .. "_" .. subfactory.id
    local checkbox = table_subfactories.add{type="checkbox", name="fp_checkbox_porter_subfactory_" .. identifier,
      state=false, enabled=(enable_checkbox or subfactory.valid)}

    local subfactory_icon = ""
    if subfactory.icon ~= nil then
        local _, sprite_rich_text = ui_util.verify_subfactory_icon(subfactory)
        subfactory_icon = sprite_rich_text .. "  "
    end
    local label = table_subfactories.add{type="label", caption=subfactory_icon .. subfactory.name}
    label.style.right_margin = 4

    local validity_caption = (subfactory.valid) and {"fp.valid"} or {"fp.error_message", {"fp.invalid"}}
    table_subfactories.add{type="label", caption=validity_caption}

    if location_name then table_subfactories.add{type="label", caption={"fp." .. location_name}} end

    ui_elements.table_rows[identifier] = {
        checkbox = checkbox,
        subfactory = subfactory
    }
end


-- Tries importing the given string, showing the resulting subfactories-table, if possible
local function import_subfactories(player)
    local modal_data = data_util.get("modal_data", player)
    local ui_elements = modal_data.ui_elements
    local content_frame = ui_elements.content_frame
    local textfield_export_string = ui_elements.import_textfield

    -- The imported subfactories will be temporarily contained in a factory object
    local import_factory, error = data_util.porter.get_subfactories(player, textfield_export_string.text)

    local function add_into_label(caption)
        local label_info = content_frame.add{type="label", caption=caption}
        label_info.style.single_line = false
        label_info.style.bottom_margin = 4
        label_info.style.width = 330
        ui_elements.info_label = label_info
    end

    if not ui_elements.porter_line then
        local line = content_frame.add{type="line", direction="horizontal"}
        line.style.margin = {6, 0, 6, 0}
        ui_elements.porter_line = line
    end

    if ui_elements.info_label then ui_elements.info_label.destroy() end
    if ui_elements.subfactories_scroll_pane then ui_elements.subfactories_scroll_pane.destroy() end

    if error ~= nil then
        add_into_label({"fp.error_message", {"fp.importer_" .. error}})
        ui_util.select_all(textfield_export_string)
    else
        add_into_label({"fp.import_instruction_2"})
        modal_data.import_factory = import_factory

        setup_subfactories_table(ui_elements, false)
        for _, subfactory in ipairs(Factory.get_in_order(import_factory, "Subfactory")) do
            add_to_subfactories_table(ui_elements, subfactory, nil, true)
        end

        ui_elements.master_checkbox.state = true
        set_all_checkboxes(player, true)
    end

    set_dialog_submit_button(ui_elements, (error == nil), "import_string")
    ui_elements.frame.force_auto_center()
end

-- Exports the currently selected subfactories and puts the resulting string into the textbox
local function export_subfactories(player)
    local ui_elements = data_util.get("ui_elements", player)
    local subfactories_to_export = {}

    for _, table_row in pairs(ui_elements.table_rows) do
        if table_row.checkbox.state == true then
            table.insert(subfactories_to_export, table_row.subfactory)
        end
    end
    local export_string = data_util.porter.get_export_string(player, subfactories_to_export)

    ui_elements.export_textfield.text = export_string
    ui_util.select_all(ui_elements.export_textfield)
end


-- ** IMPORT DIALOG **
import_dialog.dialog_settings = (function(_) return {
    caption = {"fp.two_word_title", {"fp.import"}, {"fp.pl_subfactory", 1}},
    create_content_frame = true,
    disable_scroll_pane = true
} end)

import_dialog.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_porter_subfactory_import",
            timeout = 20,
            handler = (function(player, _, _)
                import_subfactories(player)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_porter_string_import",
            handler = (function(player, element)
                local button_import = data_util.get("ui_elements", player).import_button
                set_tool_button_state(button_import, "import", (string.len(element.text) > 0))
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "fp_textfield_porter_string_import",
            handler = (function(player, element)
                if element.text ~= "" then import_subfactories(player) end
            end)
        }
    }
}


function import_dialog.open(_, modal_data)
    local ui_elements = modal_data.ui_elements
    set_dialog_submit_button(ui_elements, false, "import_string")

    local label_text = ui_elements.content_frame.add{type="label", caption={"fp.import_instruction_1"}}
    label_text.style.bottom_margin = 4

    add_textfield_and_button(ui_elements, "import", false, false)
    ui_util.select_all(ui_elements.import_textfield)
end

-- Imports the selected subfactories into the player's main factory
function import_dialog.close(player, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local factory = ui_state.context.factory

        local first_subfactory = nil
        for _, table_row in pairs(ui_state.modal_data.ui_elements.table_rows) do
            if table_row.checkbox.state == true then
                local imported_subfactory = Factory.add(factory, table_row.subfactory)
                calculation.update(player, imported_subfactory, false)
                first_subfactory = first_subfactory or imported_subfactory
            end
        end

        ui_util.context.set_subfactory(player, first_subfactory)
        main_dialog.refresh(player)
    end
end


-- ** EXPORT DIALOG **
export_dialog.dialog_settings = (function(_) return {
    caption = {"fp.two_word_title", {"fp.export"}, {"fp.pl_subfactory", 1}},
    create_content_frame = true,
    disable_scroll_pane = true
} end)

export_dialog.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_porter_subfactory_export",
            timeout = 20,
            handler = (function(player, _, _)
                export_subfactories(player)
            end)
        }
    }
}

function export_dialog.open(player, modal_data)
    local player_table = data_util.get("table", player)
    local ui_elements = modal_data.ui_elements

    local label_text = ui_elements.content_frame.add{type="label", caption={"fp.export_instruction_1"}}
    label_text.style.bottom_margin = 4

    setup_subfactories_table(ui_elements, true)

    local valid_subfactory_found = false
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            add_to_subfactories_table(ui_elements, subfactory, factory_name, false)
            valid_subfactory_found = valid_subfactory_found or subfactory.valid
        end
    end
    ui_elements.master_checkbox.enabled = valid_subfactory_found

    add_textfield_and_button(ui_elements, "export", true, false)
    ui_elements.export_textfield.parent.style.top_margin = 6
end


-- ** SHARED **
porter_dialog.gui_events = {
    on_gui_checked_state_changed = {
        {
            name = "fp_checkbox_porter_master",
            handler = (function(player, element)
                set_all_checkboxes(player, element.state)
            end)
        },
        {
            pattern = "^fp_checkbox_porter_subfactory_[a-z]+_%d+$",
            handler = (function(player, _)
                adjust_after_checkbox_click(player)
            end)
        }
    }
}
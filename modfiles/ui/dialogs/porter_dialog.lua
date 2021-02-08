import_dialog = {}
export_dialog = {}
porter_dialog = {}  -- table containing functionality shared between both dialogs

-- ** LOCAL UTIL **
local function set_tool_button_state(button, dialog_type, enabled)
    button.enabled = enabled
    button.sprite = (enabled) and ("utility/" .. dialog_type) or ("fp_sprite_" .. dialog_type .. "_light")
end

local function set_dialog_submit_button(modal_elements, enabled, action_to_take)
    local message = (not enabled) and {"fp.importer_issue_" .. action_to_take} or nil
    modal_dialog.set_submit_button_state(modal_elements, enabled, message)
end

-- Sets the state of either the export_subfactories- or dialog_submit-button
local function set_relevant_submit_button(modal_elements, dialog_type, enabled)
    if dialog_type == "export" then
        set_tool_button_state(modal_elements.export_button, dialog_type, enabled)

    else -- dialog_type == "import"
        set_dialog_submit_button(modal_elements, enabled, "select_subfactory")
    end
end


-- Sets the slave checkboxes after the master one has been clicked
local function set_all_checkboxes(player, checkbox_state)
    local ui_state = data_util.get("ui_state", player)
    local modal_elements = ui_state.modal_data.modal_elements

    for _, checkbox in pairs(modal_elements.subfactory_checkboxes) do
        if checkbox.enabled then checkbox.state = checkbox_state end
    end

    set_relevant_submit_button(modal_elements, ui_state.modal_dialog_type, checkbox_state)
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
local function adjust_after_checkbox_click(player, _, _)
    local ui_state = data_util.get("ui_state", player)
    local modal_elements = ui_state.modal_data.modal_elements

    local checked_element_count, unchecked_element_count = 0, 0
    for _, checkbox in pairs(modal_elements.subfactory_checkboxes) do
        if checkbox.state == true then checked_element_count = checked_element_count + 1
        elseif checkbox.enabled then unchecked_element_count = unchecked_element_count + 1 end
    end

    modal_elements.master_checkbox.state = (unchecked_element_count == 0)
    set_relevant_submit_button(modal_elements, ui_state.modal_dialog_type, (checked_element_count > 0))
end


-- Adds a flow containing a textfield and a button
local function add_textfield_and_button(modal_elements, dialog_type, button_first, button_enabled)
    local flow = modal_elements.content_frame.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"

    local function add_button()
        local button = flow.add{type="sprite-button", tags={on_gui_click=(dialog_type .. "_subfactories")},
          style="flib_tool_button_light_green", tooltip={"fp." .. dialog_type .. "_button_tooltip"},
          mouse_button_filter={"left"}}
        set_tool_button_state(button, dialog_type, button_enabled)
        modal_elements[dialog_type .. "_button"] = button
    end

    local function add_textfield()
        local tags = (dialog_type == "import") and
          {on_gui_text_changed="import_string", on_gui_confirmed="import_string"} or nil
        local textfield = flow.add{type="textfield", tags=tags}
        ui_util.setup_textfield(textfield)
        textfield.style.width = 0  -- needs to be set to 0 so stretching works
        textfield.style.minimal_width = 280
        textfield.style.horizontally_stretchable = true

        if button_first then textfield.style.left_margin = 6
        else textfield.style.right_margin = 6 end

        modal_elements[dialog_type .. "_textfield"] = textfield
    end

    if button_first then add_button(); add_textfield()
    else add_textfield(); add_button() end
end


-- Initializes the subfactories table by adding it and its header
local function setup_subfactories_table(modal_elements, add_location)
    modal_elements.subfactory_checkboxes = {}  -- setup for later use in add_to_subfactories_table

    local scroll_pane = modal_elements.content_frame.add{type="scroll-pane", style="flib_naked_scroll_pane_no_padding"}
    scroll_pane.style.maximal_height = 450  -- I hate that I have to set this, seemingly
    modal_elements.subfactories_scroll_pane = scroll_pane

    local frame_subfactories = scroll_pane.add{type="frame", style="deep_frame_in_shallow_frame"}
    frame_subfactories.style.padding = {-2, 2, 3, 2}

    local table_columns = {
        [2] = {caption={"fp.pu_subfactory", 2}, alignment="left", margin={6, 130, 6, 4}},
        [3] = {caption={"fp.validity"}}
    }
    if add_location then table_columns[4] = {caption={"fp.location"}} end

    local table_subfactories = frame_subfactories.add{type="table", style="mods_table",
      column_count=(table_size(table_columns) + 1)}
    modal_elements.subfactories_table = table_subfactories

    -- Add master checkbox in any case
    local checkbox_master = table_subfactories.add{type="checkbox", state=false,
      tags={on_gui_checked_state_changed="toggle_porter_master_checkbox"}}
    modal_elements.master_checkbox = checkbox_master

    for column_nr, table_column in pairs(table_columns) do
        table_subfactories.style.column_alignments[column_nr] = table_column.alignment or "center"

        local label_column = table_subfactories.add{type="label", caption=table_column.caption}
        label_column.style.font = "heading-3"
        label_column.style.margin = table_column.margin or {0, 4}
    end
end

-- Adds a row to the subfactories table
local function add_to_subfactories_table(modal_elements, subfactory, location_name, enable_checkbox)
    local table_subfactories = modal_elements.subfactories_table

    local checkbox = table_subfactories.add{type="checkbox", state=false, enabled=(enable_checkbox or subfactory.valid),
      tags={on_gui_checked_state_changed="toggle_porter_checkbox"}}

    local label = table_subfactories.add{type="label", caption=Subfactory.tostring(subfactory, true)}
    label.style.maximal_width = 350
    label.style.right_margin = 4

    local validity_caption = (subfactory.valid) and {"fp.valid"} or {"fp.error_message", {"fp.invalid"}}
    table_subfactories.add{type="label", caption=validity_caption}

    if location_name then table_subfactories.add{type="label", caption={"fp." .. location_name}} end

    local identifier = (location_name or "tmp") .. "_" .. subfactory.id
    modal_elements.subfactory_checkboxes[identifier] = checkbox
end


-- Tries importing the given string, showing the resulting subfactories-table, if possible
local function import_subfactories(player, _, _)
    local modal_data = data_util.get("modal_data", player)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame
    local textfield_export_string = modal_elements.import_textfield

    -- The imported subfactories will be temporarily contained in a factory object
    local import_factory, error = data_util.porter.get_subfactories(textfield_export_string.text)

    local function add_into_label(caption)
        local label_info = content_frame.add{type="label", caption=caption}
        label_info.style.single_line = false
        label_info.style.bottom_margin = 4
        label_info.style.width = 330
        modal_elements.info_label = label_info
    end

    if not modal_elements.porter_line then
        local line = content_frame.add{type="line", direction="horizontal"}
        line.style.margin = {6, 0, 6, 0}
        modal_elements.porter_line = line
    end

    if modal_elements.info_label then modal_elements.info_label.destroy() end
    if modal_elements.subfactories_scroll_pane then modal_elements.subfactories_scroll_pane.destroy() end

    if error ~= nil then
        add_into_label({"fp.error_message", {"fp.importer_" .. error}})
        ui_util.select_all(textfield_export_string)
    else
        add_into_label({"fp.import_instruction_2"})

        setup_subfactories_table(modal_elements, false)
        modal_data.subfactories = {}

        local any_invalid_subfactories = true
        for _, subfactory in ipairs(Factory.get_in_order(import_factory, "Subfactory")) do
            add_to_subfactories_table(modal_elements, subfactory, nil, true)
            modal_data.subfactories["tmp_" .. subfactory.id] = subfactory
            any_invalid_subfactories = any_invalid_subfactories or (not subfactory.valid)
        end

        if any_invalid_subfactories then
            modal_data.export_modset = import_factory.export_modset

            local diff_tooltip = data_util.porter.format_modset_diff(import_factory.export_modset)
            if diff_tooltip ~= "" then
                modal_elements.info_label.caption = {"fp.info_label", {"fp.import_instruction_2"}}
                modal_elements.info_label.tooltip = diff_tooltip
            end
        end

        modal_elements.master_checkbox.state = true
        set_all_checkboxes(player, true)
    end

    set_dialog_submit_button(modal_elements, (error == nil), "import_string")
    modal_elements.modal_frame.force_auto_center()
end

-- Exports the currently selected subfactories and puts the resulting string into the textbox
local function export_subfactories(player, _, _)
    local modal_data = data_util.get("modal_data", player)
    local modal_elements = modal_data.modal_elements
    local subfactories_to_export = {}

    for subfactory_identifier, checkbox in pairs(modal_elements.subfactory_checkboxes) do
        if checkbox.state == true then
            local subfactory = modal_data.subfactories[subfactory_identifier]
            table.insert(subfactories_to_export, subfactory)
        end
    end
    local export_string = data_util.porter.get_export_string(subfactories_to_export)

    modal_elements.export_textfield.text = export_string
    ui_util.select_all(modal_elements.export_textfield)
end


-- ** IMPORT DIALOG **
import_dialog.dialog_settings = (function(_) return {
    caption = {"fp.two_word_title", {"fp.import"}, {"fp.pl_subfactory", 1}},
    subheader_text = {"fp.import_instruction_1"},
    create_content_frame = true,
    disable_scroll_pane = true,
    show_submit_button = true
} end)

function import_dialog.open(_, modal_data)
    local modal_elements = modal_data.modal_elements
    set_dialog_submit_button(modal_elements, false, "import_string")

    add_textfield_and_button(modal_elements, "import", false, false)
    ui_util.select_all(modal_elements.import_textfield)
end

-- Imports the selected subfactories into the player's main factory
function import_dialog.close(player, action)
    if action == "submit" then
        local ui_state = data_util.get("ui_state", player)
        local modal_data = ui_state.modal_data
        local factory = ui_state.context.factory

        local first_subfactory = nil
        for subfactory_identifier, checkbox in pairs(modal_data.modal_elements.subfactory_checkboxes) do
            if checkbox.state == true then
                local subfactory = modal_data.subfactories[subfactory_identifier]
                local imported_subfactory = Factory.add(factory, subfactory)

                if not imported_subfactory.valid then  -- carry over modset if need be
                    imported_subfactory.last_valid_modset = modal_data.export_modset
                end

                calculation.update(player, imported_subfactory)
                first_subfactory = first_subfactory or imported_subfactory
            end
        end

        ui_util.context.set_subfactory(player, first_subfactory)
        main_dialog.refresh(player, "all")
    end
end

import_dialog.gui_events = {
    on_gui_click = {
        {
            name = "import_subfactories",
            timeout = 20,
            handler = import_subfactories
        }
    },
    on_gui_text_changed = {
        {
            name = "import_string",
            handler = (function(player, _, metadata)
                local button_import = data_util.get("modal_elements", player).import_button
                set_tool_button_state(button_import, "import", (string.len(metadata.text) > 0))
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "import_string",
            handler = (function(player, _, metadata)
                if metadata.text ~= "" then import_subfactories(player) end
            end)
        }
    }
}


-- ** EXPORT DIALOG **
export_dialog.dialog_settings = (function(_) return {
    caption = {"fp.two_word_title", {"fp.export"}, {"fp.pl_subfactory", 1}},
    subheader_text = {"fp.export_instruction"},
    subheader_tooltip = {"fp.export_instruction_tt"},
    create_content_frame = true,
    disable_scroll_pane = true
} end)

function export_dialog.open(player, modal_data)
    local player_table = data_util.get("table", player)
    local modal_elements = modal_data.modal_elements

    setup_subfactories_table(modal_elements, true)
    modal_data.subfactories = {}

    local valid_subfactory_found = false
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            add_to_subfactories_table(modal_elements, subfactory, factory_name, false)
            modal_data.subfactories[factory_name .. "_" .. subfactory.id] = subfactory
            valid_subfactory_found = valid_subfactory_found or subfactory.valid
        end
    end
    modal_elements.master_checkbox.enabled = valid_subfactory_found

    add_textfield_and_button(modal_elements, "export", true, false)
    modal_elements.export_textfield.parent.style.top_margin = 6
end

export_dialog.gui_events = {
    on_gui_click = {
        {
            name = "export_subfactories",
            timeout = 20,
            handler = export_subfactories
        }
    }
}


-- ** SHARED **
porter_dialog.gui_events = {
    on_gui_checked_state_changed = {
        {
            name = "toggle_porter_master_checkbox",
            handler = (function(player, _, metadata)
                set_all_checkboxes(player, metadata.state)
            end)
        },
        {
            name = "toggle_porter_checkbox",
            handler = adjust_after_checkbox_click
        }
    }
}

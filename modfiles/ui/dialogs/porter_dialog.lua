import_dialog = {}
export_dialog = {}
porter_dialog = {}  -- table containing functionality shared between both dialogs

-- ** LOCAL UTIL **
-- Updates the enabled-state and sprite of the given button
local function set_tool_button_state(button, dialog_type, enabled)
    button.enabled = enabled
    button.sprite = (enabled) and ("utility/" .. dialog_type) or ("fp_sprite_" .. dialog_type .. "_light")
end

-- Sets the state of either the export subfactories- or submit import dialog-button
local function set_relevant_submit_button(content_frame, dialog_type, enabled)
    if dialog_type == "export" then
        local button = content_frame["flow_export_subfactories"]["fp_button_porter_subfactory_export"]
        set_tool_button_state(button, dialog_type, enabled)

    else -- dialog_type == "import"
        content_frame.parent.parent["flow_modal_dialog_button_bar"]["fp_button_modal_dialog_submit"].enabled = enabled
    end
end


-- Adds the barebones dialog structure that both dialogs need
local function initialize_dialog(flow_modal_dialog, dialog_type)
    flow_modal_dialog.parent.caption = {"", {"fp." .. dialog_type}, " ", {"fp.pl_subfactory", 1}}
    flow_modal_dialog.vertical_scroll_policy = "never"

    local content_frame = flow_modal_dialog.add{type="frame", name="frame_content", direction="vertical",
      style="inside_shallow_frame_with_padding"}

    local label_text = content_frame.add{type="label", caption={"fp." .. dialog_type .. "_instruction_1"}}
    label_text.style.bottom_margin = 10

    return content_frame
end

-- Adds a flow containing a textfield and a button
local function add_textfield_and_button(parent_flow, dialog_type, button_first, button_enabled)
    local flow = parent_flow.add{type="flow", name="flow_" .. dialog_type .. "_subfactories", direction="horizontal"}
    flow.style.vertical_align = "center"

    local function add_button()
        local button = flow.add{type="sprite-button", name="fp_button_porter_subfactory_" .. dialog_type,
          style="fp_sprite-button_tool_green", tooltip={"fp." .. dialog_type .. "_button_tooltip"},
          mouse_button_filter={"left"}}
        set_tool_button_state(button, dialog_type, button_enabled)
    end

    local function add_textfield()
        local textfield_export_string = flow.add{type="textfield", name="fp_textfield_porter_string_" .. dialog_type}
        ui_util.setup_textfield(textfield_export_string)
        textfield_export_string.style.width = 0  -- needs to be set to 0 so stretching works
        textfield_export_string.style.minimal_width = 280
        textfield_export_string.style.horizontally_stretchable = true

        if button_first then textfield_export_string.style.left_margin = 6
        else textfield_export_string.style.right_margin = 6 end
    end

    if button_first then add_button(); add_textfield()
    else add_textfield(); add_button() end

    return flow
end

-- Initializes the subfactories table by adding it and its header
local function setup_subfactories_table(parent_flow, add_location)
    local modal_data = data_util.get("modal_data", parent_flow.player_index)
    modal_data.table_rows = {}

    local scroll_pane_subfactories = parent_flow.add{type="scroll-pane", name="scroll_pane_subfactories",
      style="scroll_pane_in_shallow_frame"}
    scroll_pane_subfactories.style.extra_top_padding_when_activated = 0
    scroll_pane_subfactories.style.extra_right_padding_when_activated = 0
    scroll_pane_subfactories.style.extra_bottom_padding_when_activated = 0
    scroll_pane_subfactories.style.extra_left_padding_when_activated = 0
    scroll_pane_subfactories.style.maximal_height = 450  -- I hate that I have to set this, seemingly

    local frame_subfactories = scroll_pane_subfactories.add{type="frame", name="frame_subfactories",
      style="deep_frame_in_shallow_frame"}
    frame_subfactories.style.padding = {-2, 2, 3, 2}

    local table_columns = {
        [2] = {caption={"fp.pu_subfactory", 2}, alignment="left", margin={6, 130, 6, 4}},
        [3] = {caption={"fp.validity"}}
    }
    if add_location then table_columns[4] = {caption={"fp.location"}} end

    local table_subfactories = frame_subfactories.add{type="table", name="table_subfactories",
      column_count=(table_size(table_columns) + 1), style="mods_table"}

    -- Add master checkbox in any case
    table_subfactories.add{type="checkbox", name="fp_checkbox_porter_master", state=false}

    for column_nr, table_column in pairs(table_columns) do
        table_subfactories.style.column_alignments[column_nr] = table_column.alignment or "center"

        local label_column = table_subfactories.add{type="label", caption=table_column.caption}
        label_column.style.font = "heading-3"
        label_column.style.margin = table_column.margin or {0, 4}
    end

    return table_subfactories, modal_data.table_rows
end

-- Adds a row to the subfactories table
local function add_to_subfactories_table(table_subfactories, table_rows, subfactory, location_name, enable_checkbox)
    local identifier = (location_name or "tmp") .. "_" .. subfactory.id
    local checkbox = table_subfactories.add{type="checkbox", name="fp_checkbox_porter_subfactory_" .. identifier,
      state=false, enabled=(enable_checkbox or subfactory.valid)}

    local subfactory_icon = " "
    if subfactory.icon ~= nil then
        local subfactory_sprite = subfactory.icon.type .. "/" .. subfactory.icon.name
        if not game.is_valid_sprite_path(subfactory_sprite) then subfactory_sprite = "utility/danger_icon" end
        subfactory_icon = " [img=" .. subfactory_sprite .. "]  "
    end
    table_subfactories.add{type="label", caption=subfactory_icon .. subfactory.name}

    local validity_caption = (subfactory.valid) and {"fp.valid"} or {"fp.error_message", {"fp.invalid"}}
    table_subfactories.add{type="label", caption=validity_caption}

    if location_name then table_subfactories.add{type="label", caption={"fp." .. location_name}} end

    table_rows[identifier] = {
        checkbox = checkbox,
        subfactory = subfactory
    }
end


-- ** IMPORT DIALOG **
function import_dialog.open(_, flow_modal_dialog, _)
    flow_modal_dialog.parent["flow_modal_dialog_button_bar"]["fp_button_modal_dialog_submit"].enabled = false

    local content_frame = initialize_dialog(flow_modal_dialog, "import")

    local flow_tf_b = add_textfield_and_button(content_frame, "import", false, false)
    ui_util.select_all(flow_tf_b["fp_textfield_porter_string_import"])
end

-- En/Disables the import-button depending on the import textfield contents
function import_dialog.handle_import_string_change(player, textfield_import)
    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    local button_import = content_frame["flow_import_subfactories"]["fp_button_porter_subfactory_import"]
    set_tool_button_state(button_import, "import", (string.len(textfield_import.text) > 0))
end

-- Tries importing the given string, showing the resulting subfactories-table, if possible
function import_dialog.import_subfactories(player)
    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]

    local textfield_export_string = content_frame["flow_import_subfactories"]["fp_textfield_porter_string_import"]
    -- The imported subfactories will be temporarily contained in a factory object
    local import_factory, error = data_util.porter.get_subfactories(player, textfield_export_string.text)

    local function add_into_label(caption)
        local label_info = content_frame.add{type="label", name="label_import_info", caption=caption}
        label_info.style.single_line = false
        label_info.style.bottom_margin = 8
        label_info.style.maximal_width = 325
    end

    if not content_frame["line_porter"] then
        local line = content_frame.add{type="line", name="line_porter", direction="horizontal"}
        line.style.margin = {10, 0, 8, 0}
    end

    if content_frame["label_import_info"] then content_frame["label_import_info"].destroy() end
    if content_frame["scroll_pane_subfactories"] then content_frame["scroll_pane_subfactories"].destroy() end

    if error ~= nil then
        add_into_label({"fp.error_message", {"fp.importer_" .. error}})
        ui_util.select_all(textfield_export_string)
    else
        add_into_label({"fp.import_instruction_2"})
        data_util.get("modal_data", player).import_factory = import_factory

        local table_subfactories, table_rows = setup_subfactories_table(content_frame, false)
        for _, subfactory in ipairs(Factory.get_in_order(import_factory, "Subfactory")) do
            add_to_subfactories_table(table_subfactories, table_rows, subfactory, nil, true)
        end

        table_subfactories["fp_checkbox_porter_master"].state = true
        porter_dialog.set_all_checkboxes(player, true)
    end

    content_frame.parent.parent.force_auto_center()
end

-- Imports the selected subfactories into the player's main factory
-- The action can only be "submit" here, and at least one subfactory will be selected
function import_dialog.close(player, _, _)
    local ui_state = data_util.get("modal_data", player)
    local factory = ui_state.context.factory

    local first_subfactory = nil
    for _, table_row in pairs(ui_state.modal_data.table_rows) do
        if table_row.checkbox.state == true then
            local imported_subfactory = Factory.add(factory, table_row.subfactory)
            calculation.update(player, imported_subfactory, false)
            first_subfactory = first_subfactory or imported_subfactory
        end
    end

    ui_util.context.set_subfactory(player, first_subfactory)
    main_dialog.refresh(player)
end


-- ** EXPORT DIALOG **
function export_dialog.open(player, flow_modal_dialog, _)
    local content_frame = initialize_dialog(flow_modal_dialog, "export")

    local table_subfactories, table_rows = setup_subfactories_table(content_frame, true)
    local valid_subfactory_found = false

    local player_table = data_util.get("table", player)
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            add_to_subfactories_table(table_subfactories, table_rows, subfactory, factory_name, false)
            valid_subfactory_found = valid_subfactory_found or subfactory.valid
        end
    end
    table_subfactories["fp_checkbox_porter_master"].enabled = valid_subfactory_found

    local flow_tf_b = add_textfield_and_button(content_frame, "export", true, false)
    flow_tf_b.style.top_margin = 10
end

-- Exports the currently selected subfactories and puts the resulting string into the textbox
function export_dialog.export_subfactories(player)
    local table_rows = data_util.get("modal_data", player).table_rows
    local subfactories_to_export = {}

    for _, table_row in pairs(table_rows) do
        if table_row.checkbox.state == true then
            table.insert(subfactories_to_export, table_row.subfactory)
        end
    end
    local export_string = data_util.porter.get_export_string(player, subfactories_to_export)

    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    local textfield_export_string = content_frame["flow_export_subfactories"]["fp_textfield_porter_string_export"]
    textfield_export_string.text = export_string
    ui_util.select_all(textfield_export_string)
end


-- ** SHARED **
function porter_dialog.set_all_checkboxes(player, checkbox_state)
    local ui_state = data_util.get("ui_state", player)

    for _, table_row in pairs(ui_state.modal_data.table_rows) do
        if table_row.checkbox.enabled then table_row.checkbox.state = checkbox_state end
    end

    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    set_relevant_submit_button(content_frame, ui_state.modal_dialog_type, checkbox_state)
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
function porter_dialog.adjust_after_checkbox_click(player)
    local ui_state = data_util.get("ui_state", player)

    local checked_element_count, unchecked_element_count = 0, 0
    for _, table_row in pairs(ui_state.modal_data.table_rows) do
        if table_row.checkbox.state == true then checked_element_count = checked_element_count + 1
        elseif table_row.checkbox.enabled then unchecked_element_count = unchecked_element_count + 1 end
    end

    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    local table_subfactories = content_frame["scroll_pane_subfactories"]["frame_subfactories"]["table_subfactories"]
    table_subfactories["fp_checkbox_porter_master"].state = (unchecked_element_count == 0)

    set_relevant_submit_button(content_frame, ui_state.modal_dialog_type, (checked_element_count > 0))
end
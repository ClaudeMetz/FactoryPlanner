-- ** LOCAL UTIL **
local function set_dialog_submit_button(modal_elements, enabled, action_to_take)
    local message = (not enabled) and {"fp.importer_issue_" .. action_to_take} or nil
    modal_dialog.set_submit_button_state(modal_elements, enabled, message)
end

-- Sets the state of either the export_factories- or dialog_submit-button
local function set_relevant_submit_button(modal_elements, dialog_type, enabled)
    if dialog_type == "export" then
        modal_elements.export_button.enabled = enabled
    else -- dialog_type == "import"
        set_dialog_submit_button(modal_elements, enabled, "select_factory")
    end
end


-- Sets the slave checkboxes after the master one has been clicked
local function set_all_checkboxes(player, checkbox_state)
    local ui_state = util.globals.ui_state(player)
    local modal_elements = ui_state.modal_data.modal_elements

    for _, checkbox in pairs(modal_elements.factory_checkboxes) do
        if checkbox.enabled then checkbox.state = checkbox_state end
    end

    set_relevant_submit_button(modal_elements, ui_state.modal_dialog_type, checkbox_state)
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
local function adjust_after_checkbox_click(player, _, _)
    local ui_state = util.globals.ui_state(player)
    local modal_elements = ui_state.modal_data.modal_elements

    local checked_element_count, unchecked_element_count = 0, 0
    for _, checkbox in pairs(modal_elements.factory_checkboxes) do
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
        local button = flow.add{type="sprite-button", tags={mod="fp", on_gui_click=(dialog_type .. "_factories")},
            style="flib_tool_button_light_green", tooltip={"fp." .. dialog_type .. "_button_tooltip"},
            sprite="utility/" .. dialog_type, enabled=button_enabled, mouse_button_filter={"left"}}
        modal_elements[dialog_type .. "_button"] = button
    end

    local function add_textfield()
        local tags = (dialog_type == "import")
            and {mod="fp", on_gui_text_changed="import_string", on_gui_confirmed="import_string"} or nil
        local textfield = flow.add{type="textfield", tags=tags}
        textfield.style.width = 0  -- needs to be set to 0 so stretching works
        textfield.style.minimal_width = 280
        textfield.style.horizontally_stretchable = true
        textfield.lose_focus_on_confirm = true

        if button_first then textfield.style.left_margin = 6
        else textfield.style.right_margin = 6 end

        modal_elements[dialog_type .. "_textfield"] = textfield
    end

    if button_first then add_button(); add_textfield()
    else add_textfield(); add_button() end
end


-- Initializes the factories table by adding it and its header
local function setup_factories_table(modal_elements, add_location)
    modal_elements.factory_checkboxes = {}  -- setup for later use in add_to_factories_table

    local frame_factories = modal_elements.content_frame.add{type="frame", style="deep_frame_in_shallow_frame"}
    modal_elements.factories_frame = frame_factories

    local scroll_pane = frame_factories.add{type="scroll-pane", style="mods_scroll_pane"}
    scroll_pane.style.maximal_height = 450  -- I hate that I have to set this, seemingly

    local table_columns = {
        [2] = {caption={"fp.u_factory"}, alignment="left", margin={0, 100, 0, 4}},
        [3] = {caption={"fp.status"}}
    }
    if add_location then table_columns[4] = {caption={"fp.location"}} end

    local table_factories = scroll_pane.add{type="table", style="table_with_selection",
        column_count=(table_size(table_columns) + 1)}
    table_factories.style.horizontally_stretchable = true
    modal_elements.factories_table = table_factories

    -- Add master checkbox in any case
    local checkbox_master = table_factories.add{type="checkbox", state=false,
        tags={mod="fp", on_gui_checked_state_changed="toggle_porter_master_checkbox"}}
    modal_elements.master_checkbox = checkbox_master

    for column_nr, table_column in pairs(table_columns) do
        table_factories.style.column_alignments[column_nr] = table_column.alignment or "center"

        local label_column = table_factories.add{type="label", caption=table_column.caption, style="heading_2_label"}
        label_column.style.margin = table_column.margin or {0, 4}
    end
end

-- Adds a row to the factories table
local function add_to_factories_table(modal_elements, factory, enable_checkbox, attach_products)
    local table_factories = modal_elements.factories_table

    local checkbox = table_factories.add{type="checkbox", state=false, enabled=(enable_checkbox or factory.valid),
        tags={mod="fp", on_gui_checked_state_changed="toggle_porter_checkbox"}}

    local label_flow = table_factories.add{type="flow", direction="horizontal"}
    label_flow.style.maximal_width = 350
    label_flow.add{type="label", caption=factory:tostring(attach_products, true)}
    label_flow.add{type="empty-widget", style="flib_horizontal_pusher"}

    local validity_caption = (factory.valid) and {"fp.valid"} or {"fp.error_message", {"fp.invalid"}}
    table_factories.add{type="label", caption=validity_caption}

    if table_factories.column_count == 4 then  -- if location column is present
        local location = (factory.archived) and "archive" or "factory"
        table_factories.add{type="label", caption={"fp.u_" .. location}}
    end

    modal_elements.factory_checkboxes[factory.id] = checkbox
end


-- Tries importing the given string, showing the resulting factories-table, if possible
local function import_factories(player, _, _)
    local player_table = util.globals.player_table(player)
    local attach_factory_products = player_table.preferences.attach_factory_products
    local modal_data = player_table.ui_state.modal_data  ---@cast modal_data -nil
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame
    local textfield_export_string = modal_elements.import_textfield

    local import_table, error = util.porter.process_export_string(textfield_export_string.text)

    local function add_info_label(caption)
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
    if modal_elements.factories_frame then modal_elements.factories_frame.destroy() end

    if error ~= nil then
        add_info_label({"fp.error_message", {"fp.importer_" .. error}})
        util.gui.select_all(textfield_export_string)
    else
        ---@cast import_table -nil

        add_info_label({"fp.import_instruction_2"})
        setup_factories_table(modal_elements, false)
        modal_data.factories = {}

        local any_invalid_factories = true
        for _, factory in ipairs(import_table.factories) do
            factory.archived = false
            add_to_factories_table(modal_elements, factory, true, attach_factory_products)
            modal_data.factories[factory.id] = factory
            any_invalid_factories = any_invalid_factories or (not factory.valid)
        end

        if any_invalid_factories then
            modal_data.export_modset = import_table.export_modset

            local diff_tooltip = util.porter.format_modset_diff(import_table.export_modset)
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

-- Exports the currently selected factories and puts the resulting string into the textbox
local function export_factories(player, _, _)
    local modal_data = util.globals.modal_data(player)
    local modal_elements = modal_data.modal_elements
    local factories_to_export = {}

    for factory_id, checkbox in pairs(modal_elements.factory_checkboxes) do
        if checkbox.state == true then
            local factory = modal_data.factories[factory_id]
            table.insert(factories_to_export, factory)
        end
    end
    local export_string = util.porter.generate_export_string(factories_to_export)

    modal_elements.export_textfield.text = export_string
    util.gui.select_all(modal_elements.export_textfield)
end


local function open_import_dialog(_, modal_data)
    local modal_elements = modal_data.modal_elements
    set_dialog_submit_button(modal_elements, false, "import_string")

    add_textfield_and_button(modal_elements, "import", false, false)
    util.gui.select_all(modal_elements.import_textfield)
end

-- Imports the selected factories into the player's current District
local function close_import_dialog(player, action)
    if action == "submit" then
        local modal_data = util.globals.modal_data(player)  ---@cast modal_data -nil
        local district = util.context.get(player, "District")  --[[@as District]]

        local first_factory = nil
        for factory_id, checkbox in pairs(modal_data.modal_elements.factory_checkboxes) do
            if checkbox.state == true then
                local factory = modal_data.factories[factory_id]
                if not factory.valid then factory.last_valid_modset = modal_data.export_modset end
                district:insert(factory)

                solver.update(player, factory)
                first_factory = first_factory or factory
            end
        end

        util.context.set(player, first_factory)
        util.raise.refresh(player, "all", nil)
    end
end


-- ** EVENTS **
local import_listeners = {}

import_listeners.gui = {
    on_gui_click = {
        {
            name = "import_factories",
            timeout = 20,
            handler = import_factories
        }
    },
    on_gui_text_changed = {
        {
            name = "import_string",
            handler = (function(player, _, event)
                local button_import = util.globals.modal_elements(player).import_button
                button_import.enabled = (string.len(event.element.text) > 0)
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "import_string",
            handler = (function(player, _, event)
                if event.element.text ~= "" then import_factories(player) end
            end)
        }
    }
}

import_listeners.dialog = {
    dialog = "import",
    metadata = (function(_) return {
        caption = {"", {"fp.import"}, " ", {"fp.pl_factory", 1}},
        subheader_text = {"fp.import_instruction_1"},
        create_content_frame = true,
        disable_scroll_pane = true,
        show_submit_button = true
    } end),
    open = open_import_dialog,
    close = close_import_dialog
}


local function open_export_dialog(player, modal_data)
    local attach_factory_products = util.globals.preferences(player).attach_factory_products
    local district = util.context.get(player, "District")  --[[@as District]]
    local modal_elements = modal_data.modal_elements

    setup_factories_table(modal_elements, true)
    modal_data.factories = {}

    local valid_factory_found = false
    for factory in district:iterator() do
        add_to_factories_table(modal_elements, factory, false, attach_factory_products)
        modal_data.factories[factory.id] = factory
        valid_factory_found = valid_factory_found or factory.valid
    end
    modal_elements.master_checkbox.enabled = valid_factory_found

    add_textfield_and_button(modal_elements, "export", true, false)
    modal_elements.export_textfield.parent.style.top_margin = 6
end


-- ** EVENTS **
local export_listeners = {}

export_listeners.gui = {
    on_gui_click = {
        {
            name = "export_factories",
            timeout = 20,
            handler = export_factories
        }
    }
}

export_listeners.dialog = {
    dialog = "export",
    metadata = (function(_) return {
        caption = {"", {"fp.export"}, " ", {"fp.pl_factory", 1}},
        subheader_text = {"fp.info_label", {"fp.export_instruction"}},
        subheader_tooltip = {"fp.export_instruction_tt"},
        create_content_frame = true,
        disable_scroll_pane = true
    } end),
    open = open_export_dialog
}


-- ** SHARED **
local porter_listeners = {}

porter_listeners.gui = {
    on_gui_checked_state_changed = {
        {
            name = "toggle_porter_master_checkbox",
            handler = (function(player, _, event)
                set_all_checkboxes(player, event.element.state)
            end)
        },
        {
            name = "toggle_porter_checkbox",
            handler = adjust_after_checkbox_click
        }
    }
}

return { import_listeners, export_listeners, porter_listeners }

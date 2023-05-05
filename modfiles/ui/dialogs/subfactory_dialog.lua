subfactory_dialog = {}

-- ** LOCAL UTIL **
local function update_submit_button(player, _, _)
    local modal_elements = data_util.get("modal_elements", player)
    local name_length = string.len(modal_elements["subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1"))
    local issue_message = {"fp.subfactory_dialog_name_empty"}
    modal_dialog.set_submit_button_state(modal_elements, (name_length > 0), issue_message)
end

local function add_rich_text(player, tags, event)
    local modal_elements = data_util.get("modal_elements", player)
    local subfactory_name = modal_elements.subfactory_name.text
    local type, elem_value = tags.type, event.element.elem_value
    if elem_value == nil then return end  -- no need to do anything here

    if type == "signal" then
        -- Signal types are insanely stupid
        if not elem_value.name then event.element.elem_value = nil; return end
        if elem_value.type == "virtual" then type = "virtual-signal"
        else type = elem_value.type end
        elem_value = elem_value.name
    end

    local rich_text = "[" .. type .. "=" .. elem_value .. "]"
    modal_elements.subfactory_name.text = subfactory_name .. rich_text

    event.element.elem_value = nil
    update_submit_button(player)
end


-- ** TOP LEVEL **
subfactory_dialog.dialog_settings = (function(modal_data)
    return {
        caption = {"", {"fp." .. modal_data.action}, " ", {"fp.pl_subfactory", 1}},
        subheader_text = {"fp.subfactory_dialog_description"},
        create_content_frame = true,
        show_submit_button = true,
        show_delete_button = (modal_data.action == "edit")
    }
end)

function subfactory_dialog.open(player, modal_data)
    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local flow_name = content_frame.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    flow_name.add{type="label", caption={"fp.info_label", {"fp.subfactory_dialog_name"}},
        tooltip={"fp.subfactory_dialog_name_tt"}}

    local subfactory_name = (modal_data.action == "edit") and modal_data.subfactory.name or ""
    local textfield_name = flow_name.add{type="textfield", text=subfactory_name,
        tags={mod="fp", on_gui_text_changed="subfactory_name"}}
    textfield_name.style.rich_text_setting = defines.rich_text_setting.enabled
    textfield_name.style.width = 250
    textfield_name.focus()
    modal_elements["subfactory_name"] = textfield_name

    local flow_rich_text = content_frame.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    flow_rich_text.style.top_margin = 8
    flow_rich_text.add{type="label", caption={"fp.info_label", {"fp.subfactory_dialog_rich_text"}},
    tooltip={"fp.subfactory_dialog_rich_text_tt"}}

    local signal_flow = flow_rich_text.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    signal_flow.style.horizontal_spacing = 6
    signal_flow.add{type="label", caption={"fp.subfactory_dialog_signals"}}
    signal_flow.add{type="choose-elem-button", elem_type="signal", style="fp_sprite-button_inset_tiny",
        tags={mod="fp", on_gui_elem_changed="add_rich_text", type="signal"}}

    local recipe_flow = flow_rich_text.add{type="flow", direction="horizontal", style="fp_flow_horizontal_centered"}
    recipe_flow.style.horizontal_spacing = 6
    recipe_flow.add{type="label", caption={"fp.subfactory_dialog_recipes"}}
    recipe_flow.add{type="choose-elem-button", elem_type="recipe", style="fp_sprite-button_inset_tiny",
        tags={mod="fp", on_gui_elem_changed="add_rich_text", type="recipe"}}

    update_submit_button(player)
end

function subfactory_dialog.close(player, action)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.modal_data.subfactory

    if action == "submit" then
        local name_textfield = ui_state.modal_data.modal_elements.subfactory_name
        local subfactory_name = name_textfield.text:gsub("^%s*(.-)%s*$", "%1")

        if subfactory ~= nil then subfactory.name = subfactory_name
        else subfactory_list.add_subfactory(player, subfactory_name) end

        main_dialog.refresh(player, "all")

    elseif action == "delete" then
        subfactory_list.delete_subfactory(player)  -- handles archiving if necessary
    end
end


-- ** EVENTS **
subfactory_dialog.gui_events = {
    on_gui_text_changed = {
        {
            name = "subfactory_name",
            handler = update_submit_button
        }
    },
    on_gui_elem_changed = {
        {
            name = "add_rich_text",
            handler = add_rich_text
        }
    }
}

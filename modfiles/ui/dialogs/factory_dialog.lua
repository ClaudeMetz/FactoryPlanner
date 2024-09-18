-- ** LOCAL UTIL **
local function open_factory_dialog(player, modal_data)
    local id = modal_data.factory_id
    modal_data.factory = (id ~= nil) and OBJECT_INDEX[id] or nil

    local modal_elements = modal_data.modal_elements
    local content_frame = modal_elements.content_frame

    local flow_name = content_frame.add{type="flow", direction="horizontal"}
    flow_name.style.vertical_align = "center"
    flow_name.add{type="label", caption={"fp.info_label", {"fp.name"}}, tooltip={"fp.factory_dialog_name_tt"}}

    local factory_name = (modal_data.factory ~= nil) and modal_data.factory.name or ""
    local textfield_name = flow_name.add{type="textfield", text=factory_name, icon_selector=true,
        tags={mod="fp", on_gui_confirmed="factory_name"}}
    textfield_name.style.left_margin = 16
    textfield_name.focus()
    modal_elements["factory_name"] = textfield_name
end

local function close_factory_dialog(player, action)
    local modal_data = util.globals.modal_data(player)

    if action == "submit" then
        local name_textfield = modal_data.modal_elements.factory_name
        local factory_name = name_textfield.text:gsub("^%s*(.-)%s*$", "%1")

        if modal_data.factory ~= nil then modal_data.factory.name = factory_name
        else factory_list.add_factory(player, factory_name) end

        util.raise.refresh(player, "all")

    elseif action == "delete" then
        factory_list.delete_factory(player)  -- handles archiving if necessary
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_confirmed = {
        {
            name = "factory_name",
            handler = (function(player, _, _)
                util.raise.close_dialog(player, "submit")
            end)
        }
    }
}

listeners.dialog = {
    dialog = "factory",
    metadata = (function(modal_data)
        local action = (modal_data.factory_id) and {"fp.edit"} or {"fp.add"}
        return {
            caption = {"", action, " ", {"fp.pl_factory", 1}},
            subheader_text = {"fp.factory_dialog_description"},
            show_submit_button = true,
            show_delete_button = (modal_data.factory_id ~= nil)
        }
    end),
    open = open_factory_dialog,
    close = close_factory_dialog
}

return { listeners }

-- ** LOCAL UTIL **
local function open_factory_dialog(player, modal_data)
    local id = modal_data.factory_id
    modal_data.factory = (id ~= nil) and OBJECT_INDEX[id] or nil

    local content_frame = modal_data.modal_elements.content_frame
    local table_content = content_frame.add{type="table", column_count=2}
    table_content.style.horizontal_spacing = 16
    table_content.style.vertical_spacing = 8
    table_content.add{type="label", caption={"fp.info_label", {"fp.name"}}, tooltip={"fp.factory_dialog_name_tt"}}

    local factory_name = (modal_data.factory ~= nil) and modal_data.factory.name or ""
    local textfield_name = table_content.add{type="textfield", text=factory_name, icon_selector=true,
        tags={mod="fp", on_gui_confirmed="factory_name"}}
    textfield_name.focus()
    modal_data.modal_elements["factory_name"] = textfield_name

    if modal_data.factory then
        table_content.add{type="label", caption={"fp.info_label", {"fp.pu_district", 1}},
            tooltip={"fp.factory_dialog_district_tt"}}

        local district_names, this_district_index = {}, nil
        modal_data.district_index = {}  -- used to find the factory later
        for district in util.globals.player_table(player).realm:iterator() do
            table.insert(district_names, district:tostring())
            table.insert(modal_data.district_index, district.id)  -- will match dropdown index
            if district.id == modal_data.factory.parent.id then this_district_index = #district_names end
        end

        local enable = (modal_data.factory and not modal_data.factory.archived and #district_names > 1)
        local dropdown_district = table_content.add{type="drop-down", items=district_names,
            selected_index=this_district_index, enabled=enable}
        modal_data.modal_elements["district_dropdown"] = dropdown_district
    end
end

local function close_factory_dialog(player, action)
    local modal_data = util.globals.modal_data(player)

    if action == "submit" then
        local name_textfield = modal_data.modal_elements.factory_name
        local factory_name = name_textfield.text:gsub("^%s*(.-)%s*$", "%1")

        if modal_data.factory == nil then
            factory_list.add_factory(player, factory_name)
        else
            local factory = modal_data.factory
            factory.name = factory_name

            local current_district = factory.parent
            local selected_index = modal_data.modal_elements.district_dropdown.selected_index
            local selected_district = OBJECT_INDEX[modal_data.district_index[selected_index]]  --[[@as District]]

            if current_district.id ~= selected_district.id then
                local adjacent_factory = util.context.remove(player, factory)

                current_district:remove(factory)
                selected_district:insert(factory)

                util.context.set(player, adjacent_factory or current_district)
                solver.update(player, factory)  -- surface conditions change things
            end
        end

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
                util.util.close_dialog(player, "submit")
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

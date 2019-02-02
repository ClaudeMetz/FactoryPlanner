-- Creates the actionbar including the new-, edit- and delete-buttons
function add_actionbar_to(main_dialog)
    local actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}

    actionbar.add{type="button", name="fp_button_new_subfactory", caption={"button-text.new_subfactory"}, style="fp_button_action"}
    actionbar.add{type="button", name="fp_button_edit_subfactory", caption={"button-text.edit"}, style="fp_button_action"}
    actionbar.add{type="button", name="fp_button_delete_subfactory", caption={"button-text.delete"}, style="fp_button_action"}
end


-- Disables edit and delete buttons if there exist no subfactories
function refresh_actionbar(player)
    local actionbar = player.gui.center["fp_main_dialog"]["flow_action_bar"]
    local delete_button = actionbar["fp_button_delete_subfactory"]

    -- selected_subfactory_id is always 0 when there are no subfactories
    local subfactory_exists = (global["selected_subfactory_id"] ~= 0)
    actionbar["fp_button_edit_subfactory"].enabled = subfactory_exists
    delete_button.enabled = subfactory_exists

    if global["current_activity"] == "deleting_subfactory" then
        delete_button.caption = {"button-text.delete_confirm"}
        set_label_color(delete_button, "red")
    else
        delete_button.caption = {"button-text.delete"}
        set_label_color(delete_button, "white")
    end
end


-- Handles populating the subfactory dialog for either 'new'- or 'edit'-actions
function open_subfactory_dialog(flow_modal_dialog, args)
    if args.edit then
        global["current_activity"] = "editing_subfactory"

        -- Checks for invalid (= mod removed) icons and makes them blank in the modal dialog
        local subfactory = get_subfactory(global["selected_subfactory_id"])
        local icon = subfactory.icon
        if icon ~= nil then
            if not flow_modal_dialog.gui.is_valid_sprite_path("item/" .. icon) then icon = nil end
        end

        create_subfactory_dialog_structure(flow_modal_dialog, {"label.edit_subfactory"}, subfactory.name, icon)
    else
        create_subfactory_dialog_structure(flow_modal_dialog, {"label.new_subfactory"}, nil, nil)
    end
end

-- Handles submission of the subfactory dialog
function submit_subfactory_dialog(flow_modal_dialog, data)
    if global["current_activity"] == "editing_subfactory" then
        edit_subfactory(global["selected_subfactory_id"], data.name, data.icon)
    else
        add_subfactory(data.name, data.icon)
        
        global["selected_subfactory_id"] = get_subfactory_count()
        update_subfactory_order()
    end
end


-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_subfactory_data(flow_modal_dialog)
    local name = flow_modal_dialog["table_subfactory"]["textfield_subfactory_name"].text:gsub("%s+", "")
    local icon = flow_modal_dialog["table_subfactory"]["choose-elem-button_subfactory_icon"].elem_value
    local instruction_1 = flow_modal_dialog["table_conditions"]["label_subfactory_instruction_1"]
    local instruction_2 = flow_modal_dialog["table_conditions"]["label_subfactory_instruction_2"]
    local instruction_3 = flow_modal_dialog["table_conditions"]["label_subfactory_instruction_3"]

    -- Resets all error indicators
    set_label_color(instruction_1, "white")
    set_label_color(instruction_2, "white")
    set_label_color(instruction_3, "white")
    local error_present = false

    if name == "" and icon == nil then
        set_label_color(instruction_1, "red")
        error_present = true
    end

    if name:len() > 16 then
        set_label_color(instruction_2, "red")
        error_present = true
    end

    -- Matches everything that is not alphanumeric or a space
    if name ~= "" and name:match("[^%w !#&'%(%)%+%-%./%?]") then
        set_label_color(instruction_3, "red")
        error_present = true
    end

    if error_present then
        return nil
    else
        if name == "" then name = nil end
        return {name=name, icon=icon}
    end
end


-- Fills out the modal dialog to enter/edit a subfactory
function create_subfactory_dialog_structure(flow_modal_dialog, title, name, icon)
    flow_modal_dialog.parent.caption = title

    -- Conditions
    local table_conditions = flow_modal_dialog.add{type="table", name="table_conditions", column_count=1}
    table_conditions.add{type="label", name="label_subfactory_instruction_1", caption={"label.subfactory_instruction_1"}}
    table_conditions.add{type="label", name="label_subfactory_instruction_2", caption={"label.subfactory_instruction_2"}}
    table_conditions.add{type="label", name="label_subfactory_instruction_3", caption={"", {"label.subfactory_instruction_3"}, " !#&'()+-./?"}}
    table_conditions.style.bottom_padding = 6

    local table_subfactory = flow_modal_dialog.add{type="table", name="table_subfactory", column_count=2}
    table_subfactory.style.bottom_padding = 8
    -- Name
    table_subfactory.add{type="label", name="label_subfactory_name", caption={"", {"label.name"}, "    "}}
    table_subfactory.add{type="textfield", name="textfield_subfactory_name", text=name}
    table_subfactory["textfield_subfactory_name"].focus()
    -- Icon
    table_subfactory.add{type="label", name="label_subfactory_icon", caption={"label.icon"}}
    table_subfactory.add{type="choose-elem-button", name="choose-elem-button_subfactory_icon", elem_type="item", item=icon}
end


-- Handles the subfactory deletion process
function handle_subfactory_deletion(player)
    if global["current_activity"] == "deleting_subfactory" then
        delete_subfactory(global["selected_subfactory_id"])
        update_subfactory_order()

        global["current_activity"] = nil
    else
        global["current_activity"] = "deleting_subfactory"
    end
    refresh_main_dialog(player)
end
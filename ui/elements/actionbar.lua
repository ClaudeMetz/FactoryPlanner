-- Creates the actionbar including the new-, edit- and delete-buttons
function add_actionbar_to(main_dialog)
    local actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}

    actionbar.add{type="button", name="button_new_subfactory", caption={"button-text.new_subfactory"}, style="fp_button_action"}
    actionbar.add{type="button", name="button_edit_subfactory", caption={"button-text.edit_subfactory"}, style="fp_button_action"}
    actionbar.add{type="button", name="button_delete_subfactory", caption={"button-text.delete_subfactory"}, style="fp_button_action"}


    --[[ -- Preserved for later use/implementation -> Timescale adjustment
    local a = actionbar.add{type="flow", name="flow_action_bar", direction="horizontal"}
    a.style.horizontally_stretchable = true

    local flow = actionbar.add{type="flow", name="flow_speed_buttons", direction="horizontal"}
    flow.style.top_padding = 3
    flow.add{type="button", name="button_speed_1", caption="60s", style="fp_button_speed_selection"} ]]
end


-- Opens the subfactory dialog for either new or edit
function open_subfactory_dialog(player, edit)
    enter_modal_dialog(player)

    if edit then
        global["currently_editing"] = true
        local subfactory = get_subfactory(global["selected_subfactory_id"])
        create_subfactory_dialog(player, {"label.edit_subfactory"}, subfactory.name, subfactory.icon)
    else
        create_subfactory_dialog(player, {"label.new_subfactory"}, "", nil)
    end
end

-- Closes the subfactory dialog
function close_subfactory_dialog(player, save)
    local subfactory_dialog = player.gui.center["frame_modal_dialog"]

    if not save then
        exit_modal_dialog(player, false)
    else
        local data = check_subfactory_data(subfactory_dialog)
        if data ~= nil then
            if global["currently_editing"] then
                edit_subfactory(global["selected_subfactory_id"], data.name, data.icon)
                global["currently_editing"] = false
            else
                add_subfactory(data.name, data.icon)
                
                -- Sets the currently selected subfactory to the new one
                global["selected_subfactory_id"] = get_subfactory_count()
            end
            -- Only closes when correct data has been entered
            exit_modal_dialog(player, true)
        end
    end
end


-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_subfactory_data(subfactory_dialog)
    local name = subfactory_dialog["table_subfactory"]["textfield_subfactory_name"].text
    local icon = subfactory_dialog["table_subfactory"]["choose-elem-button_subfactory_icon"].elem_value
    local instruction_1 = subfactory_dialog["table_conditions"]["label_subfactory_instruction_1"]
    local instruction_2 = subfactory_dialog["table_conditions"]["label_subfactory_instruction_2"]
    local instruction_3 = subfactory_dialog["table_conditions"]["label_subfactory_instruction_3"]

    -- Reset all error indications
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

    -- matches everything that is not alphanumeric or a space
    if name ~= "" and name:match("[^%w ]") then
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


-- Constructs the subfactory dialog
function create_subfactory_dialog(player, title, name, icon)
    local subfactory_dialog = player.gui.center.add{type="frame", name="frame_modal_dialog", direction="vertical", caption=title}

    local table_conditions = subfactory_dialog.add{type="table", name="table_conditions", column_count=1}
    table_conditions.add{type="label", name="label_subfactory_instruction_1", caption={"label.subfactory_instruction_1"}}
    table_conditions.add{type="label", name="label_subfactory_instruction_2", caption={"label.subfactory_instruction_2"}}
    table_conditions.add{type="label", name="label_subfactory_instruction_3", caption={"label.subfactory_instruction_3"}}
    table_conditions.style.bottom_padding = 6

    local table_subfactory = subfactory_dialog.add{type="table", name="table_subfactory", column_count=2}
    table_subfactory.style.bottom_padding = 8
    -- Name
    table_subfactory.add{type="label", name="label_subfactory_name", caption={"", {"label.subfactory_name"}, "    "}}
    table_subfactory.add{type="textfield", name="textfield_subfactory_name", text=name}
    table_subfactory["textfield_subfactory_name"].focus()

    -- Icon
    table_subfactory.add{type="label", name="label_subfactory_icon", caption={"label.subfactory_icon"}}
    table_subfactory.add{type="choose-elem-button", name="choose-elem-button_subfactory_icon", elem_type="item", item=icon}

    -- Button Bar
    local buttonbar = subfactory_dialog.add{type="flow", name="flow_subfactory_button_bar", direction="horizontal"}
    buttonbar.add{type="button", name="button_subfactory_cancel", caption={"button-text.cancel"}, style="fp_button_with_spacing"}
    buttonbar.add{type="flow", name="flow_subfactory_buttonbar", direction="horizontal"}
    buttonbar["flow_subfactory_buttonbar"].style.width = 35
    buttonbar.add{type="button", name="button_subfactory_submit", caption={"button-text.submit"}, style="fp_button_with_spacing"}
end


-- Handles the subfactory deletion process
function handle_subfactory_deletion(player, pressed)
    local main_dialog = player.gui.center["main_dialog"]
    if main_dialog ~= nil then
        local delete_button = main_dialog["flow_action_bar"]["button_delete_subfactory"]

        -- Resets the button if any other button was pressed
        if not pressed then
            set_delete_button(delete_button, true)
        else
            if not global["currently_deleting"] then
                set_delete_button(delete_button, false)
            else
                local id = global["selected_subfactory_id"]
                delete_subfactory(id)

                set_delete_button(delete_button, true)
                refresh_subfactory_bar(player)
            end
        end
    end
end

-- Sets the delete button to either state
function set_delete_button(button, reset)
    if reset then
        button.caption = {"button-text.delete_subfactory"}
        set_label_color(button, "white")
        global["currently_deleting"] = false
    else
        button.caption = {"button-text.delete_subfactory_confirm"}
        set_label_color(button, "red")
        global["currently_deleting"] = true
    end
end
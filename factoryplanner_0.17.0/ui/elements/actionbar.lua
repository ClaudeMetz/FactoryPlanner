-- Creates the actionbar including the new-, edit- and delete-buttons
function add_actionbar_to(main_dialog)
    local actionbar = main_dialog.add{type="flow", name="flow_action_bar", direction="horizontal"}

    actionbar.add{type="button", name="fp_button_new_subfactory", caption={"button-text.new_subfactory"}, 
      style="fp_button_action"}
    actionbar.add{type="button", name="fp_button_edit_subfactory", caption={"button-text.edit"}, 
      style="fp_button_action"}
    actionbar.add{type="button", name="fp_button_delete_subfactory", caption={"button-text.delete"}, 
      style="fp_button_action"}
    actionbar.style.bottom_margin = 4

    refresh_actionbar(game.players[main_dialog.player_index])
end


-- Disables edit and delete buttons if there exist no subfactories
function refresh_actionbar(player)
    local player_table = global.players[player.index]
    local actionbar = player.gui.center["fp_main_dialog"]["flow_action_bar"]
    local delete_button = actionbar["fp_button_delete_subfactory"]

    -- selected_subfactory_id is always 0 when there are no subfactories
    local subfactory_exists = (player_table.selected_subfactory_id ~= 0)
    actionbar["fp_button_edit_subfactory"].enabled = subfactory_exists
    delete_button.enabled = subfactory_exists

    if player_table.current_activity == "deleting_subfactory" then
        delete_button.caption = {"button-text.delete_confirm"}
        delete_button.style.font =  "fp-font-bold-16p"
        ui_util.set_label_color(delete_button, "dark_red")
    else
        delete_button.caption = {"button-text.delete"}
        delete_button.style.font =  "fp-font-16p"
        ui_util.set_label_color(delete_button, "default_button")
    end
end


-- Handles populating the subfactory dialog for either 'new'- or 'edit'-actions
function open_subfactory_dialog(flow_modal_dialog, args)
    if args.edit then
        local player = game.players[flow_modal_dialog.player_index]
        global.players[player.index].current_activity = "editing_subfactory"

        -- Checks for invalid (= origin mod removed) icons and makes them blank in the modal dialog
        local subfactory = Factory.get_selected_subfactory(player)
        local icon = subfactory.icon
        if icon ~= nil then
            if not player.gui.is_valid_sprite_path(icon.type .. "/" .. icon.name) then icon = nil end
        end

        create_subfactory_dialog_structure(flow_modal_dialog, {"label.edit_subfactory"}, subfactory.name, icon)
    else
        create_subfactory_dialog_structure(flow_modal_dialog, {"label.new_subfactory"}, nil, nil)
    end
end

-- Handles submission of the subfactory dialog
function close_subfactory_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]

    if action == "submit" then
        if player_table.current_activity == "editing_subfactory" then
            local subfactory_id = player_table.selected_subfactory_id
            Subfactory.set_name(player, subfactory_id, data.name)
            Subfactory.set_icon(player, subfactory_id, data.icon)
        else
            local subfactory_id = Factory.add_subfactory(player, Subfactory.init(data.name, data.icon))
            player_table.selected_subfactory_id = subfactory_id
        end
    elseif action == "delete" then
        player_table.current_activity = "deleting_subfactory"  -- a bit of a hack
        handle_subfactory_deletion(player)
    end
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_subfactory_condition_instructions()
    return {
        data = {
            name = (function(flow_modal_dialog) return 
              flow_modal_dialog["table_subfactory"]["textfield_subfactory_name"].text:gsub("%s+", "") end),
            icon = (function(flow_modal_dialog) return 
              flow_modal_dialog["table_subfactory"]["choose-elem-button_subfactory_icon"].elem_value end)
        },
        conditions = {
            [1] = {
                label = {"label.subfactory_instruction_1"},
                check = (function(data) return (data.name == "" and data.icon == nil) end),
                show_on_edit = true
            },
            [2] = {
                label = {"label.subfactory_instruction_2"},
                check = (function(data) return (data.name:len() > 16) end),
                show_on_edit = true
            },
            [3] = {
                label = {"", {"label.subfactory_instruction_3"}, " !#&'()+-./?"},
                check = (function(data) return (data.name ~= "" and data.name:match("[^%w !#&'%(%)%+%-%./%?]")) end),
                show_on_edit = true
            }
        }
    }
end

-- Fills out the modal dialog to enter/edit a subfactory
function create_subfactory_dialog_structure(flow_modal_dialog, title, name, icon)
    flow_modal_dialog.parent.caption = title

    local table_subfactory = flow_modal_dialog.add{type="table", name="table_subfactory", column_count=2}
    table_subfactory.style.bottom_padding = 8
    -- Name
    table_subfactory.add{type="label", name="label_subfactory_name", caption={"", {"label.name"}, "    "}}
    table_subfactory.add{type="textfield", name="textfield_subfactory_name", text=name}
    table_subfactory["textfield_subfactory_name"].focus()
    -- Icon
    table_subfactory.add{type="label", name="label_subfactory_icon", caption={"label.icon"}}
    table_subfactory.add{type="choose-elem-button", name="choose-elem-button_subfactory_icon", elem_type="signal",
      signal=icon}
end


-- Handles the subfactory deletion process
function handle_subfactory_deletion(player)
    local player_table = global.players[player.index]

    if player_table.current_activity == "deleting_subfactory" then
        local subfactory_position = Subfactory.get_gui_position(player, player_table.selected_subfactory_id)
        local subfactory_count = Factory.get_subfactory_count(player)
        Factory.delete_subfactory(player, player_table.selected_subfactory_id)

        -- Only if the last subfactory in the list is deleted does the selected subfactory id shift down
        if subfactory_count == subfactory_position then subfactory_position = subfactory_position - 1 end
        player_table.selected_subfactory_id = Factory.get_subfactory_id_by_position(player, subfactory_position)
        player_table.current_activity = nil
    else
        player_table.current_activity = "deleting_subfactory"
    end
    refresh_main_dialog(player)
end
-- Handles populating the subfactory dialog for either 'new'- or 'edit'-actions
function open_subfactory_dialog(flow_modal_dialog)
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]
    
    if player_table.selected_object ~= nil then  -- Meaning this is an edit

        -- Checks for invalid (= origin mod removed) icons and makes them blank in the modal dialog
        local subfactory = player_table.selected_object
        local icon = subfactory.icon
        if icon ~= nil then
            if not player.gui.is_valid_sprite_path(icon.type .. "/" .. icon.name) then icon = nil
            elseif icon.type == "virtual-signal" then icon = {name=icon.name, type="virtual"} end
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
        local subfactory = player_table.selected_object
        if subfactory ~= nil then
            subfactory.name = data.name
            Subfactory.set_icon(subfactory, data.icon)  -- Exceptional setter for edge case handling
        else
            local subfactory = Factory.add(player_table.factory, Subfactory.init(data.name, data.icon))
            data_util.context.set_subfactory(player, subfactory)
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
            -- Trim whitespace at beginning and end of the name
            name = (function(flow_modal_dialog) return
              flow_modal_dialog["table_subfactory"]["textfield_subfactory_name"].text:gsub("^%s*(.-)%s*$", "%1") end),
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
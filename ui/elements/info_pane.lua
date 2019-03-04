-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local flow = player.gui.center["fp_main_dialog"]["table_subfactory_pane"]["flow_info"]

    if flow["flow_info_elements"] == nil then
        flow.add{type="flow", name="flow_info_elements", direction="vertical"}
    else
        flow["flow_info_elements"].clear()
    end

    local player_table = global.players[player.index]

    -- Timescale
    local table_timescale = flow["flow_info_elements"].add{type="table", name="table_timescale_buttons", column_count=4}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, ": "}}
    label_timescale_title.style.top_padding = 1
    label_timescale_title.style.font = "fp-font-14p"

    if player_table.current_activity == "changing_timescale" then
        table_timescale.add{type="button", name="fp_button_timescale_1", caption="1s", style="fp_button_mini"}
        table_timescale.add{type="button", name="fp_button_timescale_60", caption="1m", style="fp_button_mini"}
        table_timescale.add{type="button", name="fp_button_timescale_3600", caption="1h", style="fp_button_mini"}
    else            
        -- As unit is limited to presets, timescale will always be displayed as 1
        local timescale = ui_util.format_timescale(Subfactory.get_timescale(player, player_table.selected_subfactory_id))
        local label_timescale = table_timescale.add{type="label", name="label_timescale", caption=timescale .. "   "}
        label_timescale.style.top_padding = 1
        label_timescale.style.font = "default-bold"
        table_timescale.add{type="button", name="fp_button_change_timescale", caption={"button-text.change"},
          style="fp_button_mini"}
    end

    -- Power Usage
    local table_energy_consumption = flow["flow_info_elements"].add{type="table", name="table_energy_consumption",
      column_count=2}
    table_energy_consumption.add{type="label", name="label_energy_consumption_title", 
      caption={"", " ",  {"label.energy_consumption"}, ": "}}
    table_energy_consumption["label_energy_consumption_title"].style.font = "fp-font-14p"

    local energy_consumption = ui_util.format_energy_consumption(
      Subfactory.get_energy_consumption(player, player_table.selected_subfactory_id), 3)

    local label_energy = table_energy_consumption.add{type="label", name="label_energy_consumption",
      caption=energy_consumption}
    label_energy.tooltip = ui_util.format_energy_consumption(Subfactory.get_energy_consumption(
      player, player_table.selected_subfactory_id), 8)
    label_energy.style.font = "default-bold"

    -- Notes
    local table_notes = flow["flow_info_elements"].add{type="table", name="table_notes", column_count=2}
    table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":   "}}
    table_notes["label_notes_title"].style.font = "fp-font-14p"
    table_notes.add{type="button", name="fp_button_view_notes", caption={"button-text.view_notes"},
      style="fp_button_mini"}
end



-- Handles the timescale changing process
function handle_subfactory_timescale_change(player, timescale)
    local player_table = global.players[player.index]
    if player_table.current_activity == "changing_timescale" then
        Subfactory.set_timescale(player, player_table.selected_subfactory_id, timescale)
        player_table.current_activity = nil
    else
        player_table.current_activity = "changing_timescale"
    end

    refresh_main_dialog(player)
end



-- Handles populating the modal dialog to view or edit notes
function open_notes_dialog(flow_modal_dialog, args)
    create_notes_dialog_structure(flow_modal_dialog, {"label.notes"})
end

-- Handles closing of the notes dialog
function close_notes_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    if action == "submit" then
        Subfactory.set_notes(player, global.players[player.index].selected_subfactory_id, data.notes)
    end
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_notes_condition_instructions()
    return {
        data = {
            notes = (function(flow_modal_dialog) return flow_modal_dialog["text-box_notes"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.notes_instruction_1"},
                check = (function(data) return (#data.notes > 65536) end),
                show_on_edit = true
            }
        }
    }
end

-- Fills out the modal dialog to view or edit notes
function create_notes_dialog_structure(flow_modal_dialog, title)
    flow_modal_dialog.parent.caption = title

    -- Notes
    local player = game.players[flow_modal_dialog.player_index]
    local text_box_notes = flow_modal_dialog.add{type="text-box", name="text-box_notes", 
      text=Subfactory.get_notes(player, global.players[player.index].selected_subfactory_id)}
    text_box_notes.focus()
    text_box_notes.style.width = 600
    text_box_notes.style.height = 400
end
-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local flow = player.gui.center["fp_main_dialog"]["table_subfactory_pane"]["flow_info"]

    if flow["flow_info_elements"] == nil then
        flow.add{type="flow", name="flow_info_elements", direction="vertical"}
    else
        flow["flow_info_elements"].clear()
    end

    -- Timescale
    local timescale = get_subfactory_timescale(global["selected_subfactory_id"])
    local unit = determine_unit(timescale)
    local table_timescale = flow["flow_info_elements"].add{type="table", name="table_timescale_buttons", column_count=4}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, ": "}}
    label_timescale_title.style.top_padding = 1
    label_timescale_title.style.font = "fp-label-large"

    if global["current_activity"] == "changing_timescale" then
        table_timescale.add{type="button", name="fp_button_timescale_1", caption="1s", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="fp_button_timescale_60", caption="1m", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="fp_button_timescale_3600", caption="1h", style="fp_button_speed_selection"}
    else            
        -- As unit is limited to presets, timescale will always be displayed as 1
        local label_timescale = table_timescale.add{type="label", name="label_timescale", caption="1" .. unit .. "   "}
        label_timescale.style.top_padding = 1
        label_timescale.style.font = "default-bold"
        table_timescale.add{type="button", name="fp_button_change_timescale", caption={"button-text.change"},
          style="fp_button_speed_selection"}
    end

    -- Power Usage
    local table_power_usage = flow["flow_info_elements"].add{type="table", name="table_power_usage", column_count=2}
    table_power_usage.add{type="label", name="label_power_usage_title", caption={"", " ",  {"label.power_usage"}, ": "}}
    table_power_usage["label_power_usage_title"].style.font = "fp-label-large"
    local power_usage = "14.7 MW"  -- Placeholder until a later implementation
    table_power_usage.add{type="label", name="label_power_usage", caption=power_usage .. "/" .. unit}
    table_power_usage["label_power_usage"].style.font = "default-bold"

    -- Notes
    local table_notes = flow["flow_info_elements"].add{type="table", name="table_notes", column_count=2}
    table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":   "}}
    table_notes["label_notes_title"].style.font = "fp-label-large"
    table_notes.add{type="button", name="fp_button_view_notes", caption={"button-text.view_notes"},
      style="fp_button_speed_selection"}
end


-- Handles the timescale changing process
function handle_subfactory_timescale_change(player, timescale)
    if global["current_activity"] == "changing_timescale" then
        set_subfactory_timescale(global["selected_subfactory_id"], timescale)
        global["current_activity"] = nil
    else
        global["current_activity"] = "changing_timescale"
    end

    refresh_main_dialog(player)
end


-- Handles populating the modal dialog to view or edit notes
function open_notes_dialog(flow_modal_dialog, args)
    create_notes_dialog_structure(flow_modal_dialog, {"label.notes"})
end

-- Handles submission of the notes dialog
function submit_notes_dialog(flow_modal_dialog, data)
    set_subfactory_notes(global["selected_subfactory_id"], data.notes)
end

-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_notes_data(flow_modal_dialog)
    local notes = flow_modal_dialog["text-box_notes"].text
    local instruction_1 = flow_modal_dialog["table_conditions"]["label_notes_instruction_1"]

    if #notes > 65536 then
        set_label_color(instruction_1, "red")
        return nil
    else
        return {notes=notes}
    end
end

-- Fills out the modal dialog to view or edit notes
function create_notes_dialog_structure(flow_modal_dialog, title)
    flow_modal_dialog.parent.caption = title

    -- Conditions
    local table_conditions = flow_modal_dialog.add{type="table", name="table_conditions", column_count=1}
    table_conditions.add{type="label", name="label_notes_instruction_1", caption={"label.notes_instruction_1"}}
    table_conditions.style.bottom_padding = 6

    -- Notes
    local text_box_notes = flow_modal_dialog.add{type="text-box", name="text-box_notes", 
      text=get_subfactory_notes(global["selected_subfactory_id"])}
    text_box_notes.focus()
    text_box_notes.style.width = 600
    text_box_notes.style.height = 400
end
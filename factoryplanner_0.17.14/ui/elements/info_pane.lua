-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory

    local flow = player.gui.center["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_info"]["scroll-pane"]
    flow.style.left_margin = 0

    if flow["table_info_elements"] == nil then
        flow.add{type="table", name="table_info_elements", column_count=1}
        flow["table_info_elements"].style.vertical_spacing = 6
    else
        flow["table_info_elements"].clear()
    end
    
    -- Timescale
    local table_timescale = flow["table_info_elements"].add{type="table", name="table_timescale_buttons", column_count=4}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, ": "}}
    label_timescale_title.style.font = "fp-font-14p"

    if ui_state.current_activity == "changing_timescale" then
        table_timescale.add{type="button", name="fp_button_timescale_1", caption="1s", style="fp_button_mini", 
          mouse_button_filter={"left"}}
        table_timescale.add{type="button", name="fp_button_timescale_60", caption="1m", style="fp_button_mini",
          mouse_button_filter={"left"}}
        table_timescale.add{type="button", name="fp_button_timescale_3600", caption="1h", style="fp_button_mini", 
          mouse_button_filter={"left"}}
    else            
        -- As unit is limited to presets, timescale will always be displayed as 1
        local timescale = ui_util.format_timescale(subfactory.timescale, false)
        local label_timescale = table_timescale.add{type="label", name="label_timescale", caption=timescale .. "   "}
        label_timescale.style.font = "default-bold"
        table_timescale.add{type="button", name="fp_button_change_timescale", caption={"button-text.change"},
          style="fp_button_mini", mouse_button_filter={"left"}}
    end

    -- Power Usage
    local table_energy_consumption = flow["table_info_elements"].add{type="table", name="table_energy_consumption",
      column_count=2}
    table_energy_consumption.add{type="label", name="label_energy_consumption_title", 
      caption={"", " ",  {"label.energy_consumption"}, ": "}}
    table_energy_consumption["label_energy_consumption_title"].style.font = "fp-font-14p"

    local energy_consumption = ui_util.format_energy_consumption(subfactory.energy_consumption, 3)
    local label_energy = table_energy_consumption.add{type="label", name="label_energy_consumption",
      caption=energy_consumption}
    label_energy.tooltip = ui_util.format_energy_consumption(subfactory.energy_consumption, 5)
    label_energy.style.font = "default-bold"

    -- Notes
    local table_notes = flow["table_info_elements"].add{type="table", name="table_notes", column_count=2}
    table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":  "}}
    table_notes["label_notes_title"].style.font = "fp-font-14p"
    table_notes.add{type="button", name="fp_button_view_notes", caption={"button-text.view_notes"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- Setting preferred machines
    local table_notes = flow["table_info_elements"].add{type="table", name="table_set_prefmachines", column_count=3}
    table_notes.add{type="label", name="label_prefmachines_title", caption={"", " ",  {"label.set_preferred_machines"}, ":  "}}
    table_notes["label_prefmachines_title"].style.font = "fp-font-14p"
    table_notes.add{type="button", name="fp_button_set_prefmachines_subfactory", caption={"button-text.subfactory"}, 
      style="fp_button_mini", tooltip={"tooltip.set_preferred_machines_subfactory"}, mouse_button_filter={"left"}}
    table_notes.add{type="button", name="fp_button_set_prefmachines_floor", caption={"button-text.floor"}, 
      style="fp_button_mini", tooltip={"tooltip.set_preferred_machines_floor"}, mouse_button_filter={"left"}}
end


-- Handles the timescale changing process
function handle_subfactory_timescale_change(player, timescale)
    local ui_state = get_ui_state(player)
    if ui_state.current_activity == "changing_timescale" then
        local subfactory = ui_state.context.subfactory
        subfactory.timescale = timescale
        ui_state.current_activity = nil
        update_calculations(player, subfactory)
    else
        ui_state.current_activity = "changing_timescale"
    end

    refresh_main_dialog(player)
end


-- Sets the machines of all lines in the given scope to the currently preferred ones
function handle_set_prefmachines_click(player, scope)
    local context = get_context(player)

    -- Sets all machines on given floor to the currently preferred ones
    local function set_machines_on_floor(floor)
        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            data_util.machines.change_machine(player, line, nil, nil)
            if line.subfloor ~= nil then
                Floor.get(line.subfloor, "Line", 1).machine_id = line.machine_id
            end
        end
    end

    if scope == "subfactory" then
        for _, floor in ipairs(Subfactory.get_in_order(context.subfactory, "Floor")) do
            set_machines_on_floor(floor)
        end
    else  -- scope == "floor"
        set_machines_on_floor(context.floor)
    end

    update_calculations(player, context.subfactory)
    refresh_production_table(player)
end
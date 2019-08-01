-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local ui_state = get_ui_state(player)
    local context = ui_state.context
    local subfactory = context.subfactory

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

    -- Notes
    local table_notes = flow["table_info_elements"].add{type="table", name="table_notes", column_count=2}
    table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":  "}}
    table_notes["label_notes_title"].style.font = "fp-font-14p"
    table_notes.add{type="button", name="fp_button_view_notes", caption={"button-text.view_notes"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- Power Usage
    local table_energy_consumption = flow["table_info_elements"].add{type="table", name="table_energy_consumption",
      column_count=2}
    table_energy_consumption.add{type="label", name="label_energy_consumption_title", 
      caption={"", " ",  {"label.energy_consumption"}, ": "}}
    table_energy_consumption["label_energy_consumption_title"].style.font = "fp-font-14p"

    -- Show either subfactory or floor energy consumption, depending on the floor_total toggle
    local origin_line = context.floor.origin_line
    local energy_consumption = (ui_state.floor_total and origin_line ~= nil) and
      origin_line.energy_consumption or subfactory.energy_consumption
    
    local label_energy = table_energy_consumption.add{type="label", name="label_energy_consumption",
      caption=ui_util.format_SI_value(energy_consumption, "W", 3),
      tooltip=ui_util.format_SI_value(energy_consumption, "W", 5)}
    label_energy.style.font = "default-bold"

    -- Mining Productivity
    local table_mining_prod = flow["table_info_elements"].add{type="table", name="table_mining_prod", column_count=3}
    table_mining_prod.add{type="label", name="label_mining_prod_title",
      caption={"", " ",  {"label.mining_prod"}, " [img=info]: "}, tooltip={"tooltip.mining_prod"}}
    table_mining_prod["label_mining_prod_title"].style.font = "fp-font-14p"

    if ui_state.current_activity == "overriding_mining_prod" or subfactory.mining_productivity ~= nil then
        subfactory.mining_productivity = subfactory.mining_productivity or 0
        local textfield_prod_bonus = table_mining_prod.add{type="textfield", name="fp_textfield_mining_prod",
          text=(subfactory.mining_productivity or 0)}
        textfield_prod_bonus.style.width = 60
        local label_percentage = table_mining_prod.add{type="label", name="label_percentage", caption="%"}
        label_percentage.style.font = "default-bold"
    else
        local label_prod_bonus = table_mining_prod.add{type="label", name="label_mining_prod_value", 
          caption={"", player.force.mining_drill_productivity_bonus, "%"}}
        label_prod_bonus.style.font = "default-bold"
        local button_override = table_mining_prod.add{type="button", name="fp_button_mining_prod_override", 
          caption={"button-text.override"}, style="fp_button_mini", mouse_button_filter={"left"}}
        button_override.style.left_margin = 8
    end
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
        refresh_main_dialog(player)
    end
end

-- Persists changes to the overriden mining productivity
function handle_mining_prod_change(player, element)
    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = tonumber(element.text)
end
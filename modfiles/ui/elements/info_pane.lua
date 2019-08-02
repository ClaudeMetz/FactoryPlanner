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
    local table_timescale = flow["table_info_elements"].add{type="table", name="table_timescale_buttons", column_count=2}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, " [img=info]: "}, tooltip={"tooltip.timescales"}}
    label_timescale_title.style.font = "fp-font-14p"
    table_timescale.style.bottom_margin = 4

    local timescales = {["1s"] = 1, ["1m"] = 60, ["1h"] = 3600}
    local table_timescales = table_timescale.add{type="table", name="table_timescales", column_count=table_size(timescales)}
    table_timescales.style.horizontal_spacing = 0
    table_timescales.style.left_margin = 2
    for caption, scale in pairs(timescales) do  -- Factorio-Lua preserving ordering is important here
        local button = table_timescales.add{type="button", name=("fp_button_timescale_" .. scale), caption=caption,
          mouse_button_filter={"left"}}
        button.enabled = (not (subfactory.timescale == scale))
        button.style = (subfactory.timescale == scale) and "fp_button_timescale_selected" or "fp_button_timescale"
    end

    -- Notes
    local table_notes = flow["table_info_elements"].add{type="table", name="table_notes", column_count=2}
    local label_notes = table_notes.add{type="label", name="label_notes_title", caption={"", " ",  {"label.notes"}, ":  "}}
    label_notes.style.font = "fp-font-14p"
    label_notes.style.bottom_padding = 2
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
    local subfactory = get_context(player).subfactory
    subfactory.timescale = timescale
    update_calculations(player, subfactory)
end

-- Persists changes to the overriden mining productivity
function handle_mining_prod_change(player, element)
    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = tonumber(element.text)
end
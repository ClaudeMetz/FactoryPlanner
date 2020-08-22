info_pane = {}

-- ** TOP LEVEL **
-- Constructs the info pane including timescale settings
function info_pane.refresh(player)
    local ui_state = get_ui_state(player)
    local context = ui_state.context
    local subfactory = context.subfactory

    local flow = player.gui.screen["fp_frame_main_dialog"]["table_subfactory_pane"]["flow_info"]["scroll-pane"]
    flow.style.left_margin = 0

    local table_info_elements = flow["table_info_elements"]
    if table_info_elements == nil then
        table_info_elements = flow.add{type="table", name="table_info_elements", column_count=1}
        table_info_elements.style.vertical_spacing = 6
        table_info_elements.style.left_margin = 6
    else
        table_info_elements.clear()
    end


    -- Timescale
    local table_timescale = table_info_elements.add{type="table", name="table_timescale_buttons", column_count=2}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", {"fp.timescale"}, " [img=info]: "}, tooltip={"fp.timescales_tt"}}
    label_timescale_title.style.font = "fp-font-14p"
    table_timescale.style.bottom_margin = 4

    local timescales = {1, 60, 3600}
    local table_timescales = table_timescale.add{type="table", name="table_timescales",
      column_count=#timescales}
    table_timescales.style.horizontal_spacing = 0
    table_timescales.style.left_margin = 2

    for _, scale in pairs(timescales) do
        local button = table_timescales.add{type="button", name=("fp_button_timescale_" .. scale),
          caption=ui_util.format_timescale(scale), mouse_button_filter={"left"}}
        button.enabled = (not (subfactory.timescale == scale))
        button.style = (subfactory.timescale == scale) and "fp_button_timescale_selected" or "fp_button_timescale"
    end


    -- Utility dialog
    info_pane.refresh_utility_table(player, subfactory, table_info_elements)


    -- Power Usage + Pollution
    local table_energy_pollution = table_info_elements.add{type="table", name="table_energy_pollution", column_count=2}
    table_energy_pollution.draw_vertical_lines = true
    table_energy_pollution.style.horizontal_spacing = 20

    -- Show either subfactory or floor energy/pollution, depending on the floor_total toggle
    local origin_line = context.floor.origin_line
    local energy_consumption, pollution
    if ui_state.flags.floor_total and origin_line ~= nil then
        energy_consumption = origin_line.energy_consumption
        pollution = origin_line.pollution
    else
        energy_consumption = subfactory.energy_consumption
        pollution = subfactory.pollution
    end

    -- Energy consumption
    local table_energy = table_energy_pollution.add{type="table", name="table_energy", column_count=2}
    local label_energy_title = table_energy.add{type="label", name="label_energy_title",
      caption={"", {"fp.energy"}, ":"}}
    label_energy_title.style.font = "fp-font-14p"
    local label_energy_value = table_energy.add{type="label", name="label_energy_value",
      caption=ui_util.format_SI_value(energy_consumption, "W", 3),
      tooltip=ui_util.format_SI_value(energy_consumption, "W", 5)}
    label_energy_value.style.font = "default-bold"

    -- Pollution
    local table_pollution = table_energy_pollution.add{type="table", name="table_pollution", column_count=2}
    local label_pollution_title = table_pollution.add{type="label", name="label_pollution_title",
      caption={"", {"fp.cpollution"}, ":"}}
    label_pollution_title.style.font = "fp-font-14p"
    local label_pollution_value = table_pollution.add{type="label", name="label_pollution_value",
      caption={"", ui_util.format_SI_value(pollution, "P/m", 3)},
      tooltip={"", ui_util.format_SI_value(pollution, "P/m", 5)}}
    label_pollution_value.style.font = "default-bold"


    -- Mining Productivity
    info_pane.refresh_mining_prod_table(player, subfactory, table_info_elements)
end


-- Separate function so it can be refreshed independently
function info_pane.refresh_utility_table(player, subfactory, table_info_elements)
    table_info_elements = table_info_elements or player.gui.screen["fp_frame_main_dialog"]
      ["table_subfactory_pane"]["flow_info"]["scroll-pane"]["table_info_elements"]

    local table_utility = table_info_elements["table_utility"] or
      table_info_elements.add{type="table", name="table_utility", column_count=2}
    table_utility.clear()

    table_utility.add{type="label", name="label_utility", caption={"", {"fp.utility"}, ": "}}

    local table_ut = table_utility.add{type="table", name="table_ut", column_count=2}
    table_ut.style.horizontal_spacing = 20
    table_ut.add{type="button", name="fp_button_open_utility_dialog", caption={"fp.view_utilities"},
      style="fp_button_mini", mouse_button_filter={"left"}}

    -- Only show the notes tooltip-label if there are any notes to show
    if subfactory.notes ~= "" then
        table_ut.draw_vertical_lines = true

        local label_notes = table_ut.add{type="label", name="label_notes", caption={"", {"fp.notes"}, " [img=info]"}}
        label_notes.tooltip = (string.len(subfactory.notes) < 1000) and
          subfactory.notes or string.sub(subfactory.notes, 1, 1000) .. "\n[...]"
    end
end

-- Separate function so it can be refreshed independently
function info_pane.refresh_mining_prod_table(player, subfactory, table_info_elements)
    local table_mining_prod = table_info_elements["table_mining_prod"] or
      table_info_elements.add{type="table", name="table_mining_prod", column_count=3}
    table_mining_prod.clear()

    table_mining_prod.add{type="label", name="label_mining_prod_title",
      caption={"", {"fp.mining_prod"}, " [img=info]: "}, tooltip={"fp.mining_prod_tt"}}
    table_mining_prod["label_mining_prod_title"].style.font = "fp-font-14p"

    if subfactory.mining_productivity ~= nil then
        local textfield_prod_bonus = table_mining_prod.add{type="textfield", name="fp_textfield_mining_prod",
          text=subfactory.mining_productivity}
        textfield_prod_bonus.style.width = 60
        textfield_prod_bonus.style.height = 26
        ui_util.setup_numeric_textfield(textfield_prod_bonus, true, true)
        local label_percentage = table_mining_prod.add{type="label", name="label_percentage", caption="%"}
        label_percentage.style.font = "default-bold"
    else
        local prod_bonus = ui_util.format_number((player.force.mining_drill_productivity_bonus * 100), 4)
        local label_prod_bonus = table_mining_prod.add{type="label", name="label_mining_prod_value",
          caption={"", prod_bonus, "%"}}
        label_prod_bonus.style.font = "default-bold"
        local button_override = table_mining_prod.add{type="button", name="fp_button_mining_prod_override",
          caption={"fp.override"}, style="fp_button_mini", mouse_button_filter={"left"}}
        button_override.style.left_margin = 8
    end
end


-- Handles the timescale changing process
function info_pane.handle_subfactory_timescale_change(player, timescale)
    if ui_util.check_archive_status(player) then return end

    local subfactory = get_context(player).subfactory
    local old_timescale = subfactory.timescale
    subfactory.timescale = timescale

    -- Adjust the required_amount according to the new timescale
    local timescale_ratio = (timescale / old_timescale)
    for _, top_level_product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local required_amount = top_level_product.required_amount
        -- No need to change amounts for belts/lanes, as timescale change does that implicitly
        if required_amount.defined_by == "amount" then
            required_amount.amount = required_amount.amount * timescale_ratio
        end
    end

    calculation.update(player, subfactory, true)
end

-- Activates the mining prod override mode for the current subfactory
function info_pane.override_mining_prod(player)
    if ui_util.check_archive_status(player) then return end

    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = 0
    calculation.update(player, subfactory, true)
end

-- Persists changes to the overriden mining productivity
function info_pane.handle_mining_prod_change(player, element)
    if ui_util.check_archive_status(player) then return end

    local subfactory = get_context(player).subfactory
    subfactory.mining_productivity = tonumber(element.text)
end

-- Handles confirmation of the mining prod textfield, possibly disabling the custom override
function info_pane.handle_mining_prod_confirmation(player)
    local subfactory = get_context(player).subfactory
    calculation.update(player, subfactory, true)
end
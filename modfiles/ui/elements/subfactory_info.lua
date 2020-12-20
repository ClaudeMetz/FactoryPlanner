subfactory_info = {}

-- ** LOCAL UTIL **
local function repair_subfactory(player)
    -- This function can only run is a subfactory is selected and invalid
    local subfactory = data_util.get("context", player).subfactory

    Subfactory.repair(subfactory, player)

    calculation.update(player, subfactory)
    main_dialog.refresh(player, "all")  -- needs the full refresh to reset subfactory list buttons
end

local function change_timescale(player, new_timescale)
    local ui_state = data_util.get("ui_state", player)
    local subfactory = ui_state.context.subfactory

    local old_timescale = subfactory.timescale
    subfactory.timescale = new_timescale

    -- Adjust the required_amount according to the new timescale
    local timescale_ratio = (new_timescale / old_timescale)
    for _, top_level_product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
        local required_amount = top_level_product.required_amount
        -- No need to change amounts for belts/lanes, as timescale change does that implicitly
        if required_amount.defined_by == "amount" then
            required_amount.amount = required_amount.amount * timescale_ratio
        end
    end

    calculation.update(player, subfactory)
    -- View state updates itself automatically if it detects a timescale change
    main_dialog.refresh(player, "subfactory")
end


-- ** TOP LEVEL **
function subfactory_info.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.subfactory_info = {}

    local parent_flow = main_elements.flows.left_vertical
    local frame_vertical = parent_flow.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}
    frame_vertical.style.height = SUBFACTORY_INFO_HEIGHT
    frame_vertical.style.horizontally_stretchable = true
    frame_vertical.style.bottom_padding = 4  -- this makes the vertical pushers align stuff nicely

    local title = frame_vertical.add{type="label", caption={"fp.subfactory_info"}, style="caption_label"}
    title.style.top_margin = -4

    local first_pusher = frame_vertical.add{type="empty-widget", style="flib_vertical_pusher"}
    main_elements.subfactory_info["first_pusher"] = first_pusher

    -- Repair flow
    local flow_repair = frame_vertical.add{type="flow", direction="vertical"}
    flow_repair.style.top_margin = 6
    main_elements.subfactory_info["repair_flow"] = flow_repair

    local label = flow_repair.add{type="label", caption={"fp.warning_with_icon", {"fp.subfactory_needs_repair"}}}
    label.style.single_line = false
    local button_repair = flow_repair.add{type="button", name="fp_button_subfactory_repair",
      caption={"fp.repair_subfactory"}, style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    button_repair.style.top_margin = 4


    -- 'No subfactory' flow - This is very stupid
    local flow_no_subfactory = frame_vertical.add{type="flow", direction="horizontal"}
    main_elements.subfactory_info["no_subfactory_flow"] = flow_no_subfactory
    flow_no_subfactory.add{type="empty-widget", style="flib_horizontal_pusher"}
    flow_no_subfactory.add{type="label", caption={"fp.no_subfactory"}}
    flow_no_subfactory.add{type="empty-widget", style="flib_horizontal_pusher"}


    -- Subfactory info
    local flow_info = frame_vertical.add{type="flow", direction="vertical"}
    flow_info.style.vertical_spacing = 8
    main_elements.subfactory_info["info_flow"] = flow_info

    -- Power + Pollution
    local table_power_pollution = flow_info.add{type="table", column_count=2}
    table_power_pollution.draw_vertical_lines = true
    table_power_pollution.style.horizontal_spacing = 20

    local flow_power = table_power_pollution.add{type="flow", direction="horizontal"}
    flow_power.add{type="label", caption={"fp.key_title", {"fp.u_power"}}}
    local label_power_value = flow_power.add{type="label"}
    main_elements.subfactory_info["power_label"] = label_power_value

    local flow_pollution = table_power_pollution.add{type="flow", direction="horizontal"}
    flow_pollution.add{type="label", caption={"fp.key_title", {"fp.u_pollution"}}}
    local label_pollution_value = flow_pollution.add{type="label"}
    main_elements.subfactory_info["pollution_label"] = label_pollution_value

    -- Utility
    local table_utility = flow_info.add{type="table", column_count=2}
    table_utility.style.horizontal_spacing = 24
    main_elements.subfactory_info["utility_table"] = table_utility

    local flow_utility = table_utility.add{type="flow", direction="horizontal"}
    flow_utility.style.vertical_align = "center"
    flow_utility.style.horizontal_spacing = 8
    flow_utility.add{type="label", caption={"fp.key_title", {"fp.utility"}}}
    flow_utility.add{type="button", name="fp_button_view_utilities", caption={"fp.view_utilities"},
      style="fp_button_rounded_mini", mouse_button_filter={"left"}}

    local label_notes = table_utility.add{type="label", caption={"fp.info_label", {"fp.notes"}}}
    main_elements.subfactory_info["notes_label"] = label_notes

    -- Timescale
    local flow_timescale = flow_info.add{type="flow", direction="horizontal"}
    flow_timescale.style.horizontal_spacing = 10
    flow_timescale.style.top_margin = 8
    flow_timescale.style.vertical_align = "center"

    flow_timescale.add{type="label", caption={"fp.key_title", {"fp.info_label", {"fp.timescale"}}},
      tooltip={"fp.timescale_tt"}}

    local table_timescales = flow_timescale.add{type="table", column_count=table_size(TIMESCALE_MAP)}
    table_timescales.style.horizontal_spacing = 0
    main_elements.subfactory_info["timescales_table"] = table_timescales

    for scale, name in pairs(TIMESCALE_MAP) do
        table_timescales.add{type="button", name=("fp_button_change_timescale_to_" .. scale), style="fp_button_push",
          caption={"", "1", {"fp.unit_" .. name}}, mouse_button_filter={"left"}}
    end

    -- Mining productivity
    local flow_mining_prod = flow_info.add{type="flow", direction="horizontal"}
    flow_mining_prod.style.horizontal_spacing = 10
    flow_mining_prod.style.vertical_align = "center"

    flow_mining_prod.add{type="label", caption={"fp.key_title", {"fp.info_label", {"fp.mining_productivity"}}},
      tooltip={"fp.mining_productivity_tt"}}

    local label_prod_bonus = flow_mining_prod.add{type="label"}
    main_elements.subfactory_info["prod_bonus_label"] = label_prod_bonus

    local button_override_prod_bonus = flow_mining_prod.add{type="button", name="fp_button_override_mining_prod",
      caption={"fp.override"}, style="fp_button_rounded_mini", mouse_button_filter={"left"}}
    button_override_prod_bonus.style.disabled_font_color = {}
    main_elements.subfactory_info["override_prod_bonus_button"] = button_override_prod_bonus

    local textfield_prod_bonus = flow_mining_prod.add{type="textfield", name="fp_textfield_mining_prod_override"}
    textfield_prod_bonus.style.size = {60, 26}
    ui_util.setup_numeric_textfield(textfield_prod_bonus, true, true)
    main_elements.subfactory_info["prod_bonus_override_textfield"] = textfield_prod_bonus

    local label_percentage = flow_mining_prod.add{type="label", caption={"fp.bold_label", "%"}}
    main_elements.subfactory_info["percentage_label"] = label_percentage

    local second_pusher = frame_vertical.add{type="empty-widget", style="flib_vertical_pusher"}
    main_elements.subfactory_info["second_pusher"] = second_pusher

    subfactory_info.refresh(player)
end

function subfactory_info.refresh(player)
    local ui_state = data_util.get("ui_state", player)
    local subfactory_info_elements = ui_state.main_elements.subfactory_info
    local subfactory = ui_state.context.subfactory

    subfactory_info_elements.no_subfactory_flow.visible = (not subfactory)

    -- Because single_line is bugged, we need to hide the pushers when repair is shown
    local invalid_subfactory_selected = (subfactory and not subfactory.valid)
    subfactory_info_elements.repair_flow.visible = invalid_subfactory_selected
    subfactory_info_elements.first_pusher.visible = not invalid_subfactory_selected
    subfactory_info_elements.second_pusher.visible = not invalid_subfactory_selected

    local valid_subfactory_selected = (subfactory and subfactory.valid)
    subfactory_info_elements.info_flow.visible = valid_subfactory_selected

    if valid_subfactory_selected then  -- we need to refresh some stuff in this case
        local archive_open = ui_state.flags.archive_open

        -- Power + Pollution
        local label_power = subfactory_info_elements.power_label
        label_power.caption = {"fp.bold_label", ui_util.format_SI_value(subfactory.energy_consumption, "W", 3)}
        label_power.tooltip = ui_util.format_SI_value(subfactory.energy_consumption, "W", 5)

        local label_pollution = subfactory_info_elements.pollution_label
        label_pollution.caption = {"fp.bold_label", ui_util.format_SI_value(subfactory.pollution, "P/m", 3)}
        label_pollution.tooltip = ui_util.format_SI_value(subfactory.pollution, "P/m", 5)

        -- Utility
        local notes_present = (subfactory.notes ~= "")
        subfactory_info_elements.utility_table.draw_vertical_lines = notes_present
        subfactory_info_elements.notes_label.visible = notes_present

        if notes_present then
            local tooltip = (string.len(subfactory.notes) < 1000) and
              subfactory.notes or string.sub(subfactory.notes, 1, 1000) .. "\n[...]"
            subfactory_info_elements.notes_label.tooltip = tooltip
        end

        -- Timescale
        for _, button in pairs(subfactory_info_elements.timescales_table.children) do
            local timescale = tonumber(string.match(button.name, "%d+"))
            local selected = (subfactory.timescale == timescale)
            button.style = (selected) and "fp_button_push_active" or "fp_button_push"
            button.style.width = 42  -- needs to be re-set when changing the style
            button.enabled = not (selected or archive_open)
        end

        -- Mining Productivity
        local custom_prod_set = subfactory.mining_productivity

        if not custom_prod_set then  -- only do this calculation when it'll actually be shown
            local prod_bonus = ui_util.format_number((player.force.mining_drill_productivity_bonus * 100), 4)
            subfactory_info_elements.prod_bonus_label.caption = {"fp.bold_label", {"fp.percentage_title", prod_bonus}}
        end
        subfactory_info_elements.prod_bonus_label.visible = not custom_prod_set

        subfactory_info_elements.override_prod_bonus_button.enabled = (not archive_open)
        subfactory_info_elements.override_prod_bonus_button.visible = not custom_prod_set

        if custom_prod_set then  -- only change the text when the textfield will actually be shown
            subfactory_info_elements.prod_bonus_override_textfield.text = tostring(subfactory.mining_productivity)
        end
        subfactory_info_elements.prod_bonus_override_textfield.enabled = (not archive_open)
        subfactory_info_elements.prod_bonus_override_textfield.visible = custom_prod_set
        subfactory_info_elements.percentage_label.visible = custom_prod_set
    end
end


-- ** EVENTS **
subfactory_info.gui_events = {
    on_gui_click = {
        {
            name = "fp_button_subfactory_repair",
            timeout = 20,
            handler = repair_subfactory
        },
        {
            name = "fp_button_view_utilities",
            handler = (function(player, _, _)
                modal_dialog.enter(player, {type="utility"})
            end)
        },
        {
            pattern = "^fp_button_change_timescale_to_%d+$",
            handler = (function(player, element, _)
                local new_timescale = tonumber(string.match(element.name, "%d+"))
                change_timescale(player, new_timescale)
            end)
        },
        {
            name = "fp_button_override_mining_prod",
            handler = (function(player, _, _)
                local subfactory = data_util.get("context", player).subfactory
                subfactory.mining_productivity = 0
                calculation.update(player, subfactory)
                main_dialog.refresh(player, "subfactory")
            end)
        },
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_mining_prod_override",
            handler = (function(player, element)
                local ui_state = data_util.get("ui_state", player)
                ui_state.context.subfactory.mining_productivity = tonumber(element.text)
                ui_state.flags.recalculate_on_subfactory_change = true -- set flag to recalculate if necessary
            end)
        }
    },
    on_gui_confirmed = {
        {
            name = "fp_textfield_mining_prod_override",
            handler = (function(player, _)
                local ui_state = data_util.get("ui_state", player)
                ui_state.flags.recalculate_on_subfactory_change = false  -- reset this flag as we refresh
                calculation.update(player, ui_state.context.subfactory)
                main_dialog.refresh(player, "subfactory")
            end)
        }
    }
}
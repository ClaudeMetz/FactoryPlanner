-- Handles populating the preferences dialog
function open_preferences_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"label.preferences"}
    flow_modal_dialog.style.padding = 6

    -- Info
    local label_preferences_info = flow_modal_dialog.add{type="label", name="label_preferences_info", 
      caption={"label.preferences_info"}}
    label_preferences_info.style.single_line = false
    label_preferences_info.style.bottom_margin = 4

    -- General preferences
    flow_modal_dialog.add{type="label", name="label_general_info", caption={"", {"label.preferences_title_general"}, ":"},
      style="fp_preferences_title_label", tooltip={"tooltip.preferences_title_general"}}
    local table_general_prefs = flow_modal_dialog.add{type="table", name="table_general_preferences", column_count=1}
    table_general_prefs.style.top_margin = 2
    table_general_prefs.style.bottom_margin = 8
    table_general_prefs.style.left_margin = 16

    -- Ignore barreling recipes
    table_general_prefs.add{type="checkbox", name="fp_checkbox_preferences_ignore_barreling", state=false,
      caption={"", " ", {"label.preferences_ignore_barreling"}}}


    -- Belt preferences
    flow_modal_dialog.add{type="label", name="label_belts_info", caption={"", {"label.preferences_title_belts"}, ":"},
      style="fp_preferences_title_label", tooltip={"tooltip.preferences_title_belts"}}

    flow_modal_dialog.add{type="table", name="table_all_belts", column_count=12, style="fp_preferences_table"}


    -- Fuel preferences
    flow_modal_dialog.add{type="label", name="label_fuels_info", caption={"", {"label.preferences_title_fuels"}, ":"},
      style="fp_preferences_title_label", tooltip={"tooltip.preferences_title_fuels"}}

    flow_modal_dialog.add{type="table", name="table_all_fuels", column_count=12, style="fp_preferences_table"}


    -- Machine preferences
    flow_modal_dialog.add{type="label", name="label_machines_info", caption={"", {"label.preferences_title_machines"}, ":"},
      style="fp_preferences_title_label", tooltip={"tooltip.preferences_title_machines"}}

    local table_all_machines = flow_modal_dialog.add{type="table", name="table_all_machines", column_count=2}
    table_all_machines.style.top_margin = 4
    table_all_machines.style.left_padding = 6
    table_all_machines.style.bottom_padding = 4

    refresh_preferences_dialog(flow_modal_dialog.gui.player)
end


-- Creates the modal dialog to change your preferences
function refresh_preferences_dialog(player)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local preferences = get_preferences(player)

    -- General preferences
    local table_general_prefs = flow_modal_dialog["table_general_preferences"]
    table_general_prefs["fp_checkbox_preferences_ignore_barreling"].state = preferences.ignore_barreling_recipes

    -- Belt preferences
    local table_all_belts = flow_modal_dialog["table_all_belts"]
    table_all_belts.clear()

    for belt_id, belt in pairs(global.all_belts.belts) do
        local button_belt = table_all_belts.add{type="sprite-button", name="fp_sprite-button_preferences_belt_"
          .. belt_id, sprite="entity/" .. belt.name, mouse_button_filter={"left"}}
          
        local tooltip = belt.localised_name
        local preferred_belt_id = get_preferences(player).preferred_belt_id
        if preferred_belt_id == belt_id then
            button_belt.style = "fp_button_icon_medium_green"
            tooltip = {"", tooltip, "\n", {"tooltip.selected"}}
        else 
            button_belt.style = "fp_button_icon_medium_hidden"
        end
        button_belt.tooltip = tooltip
    end

    -- Fuel preferences
    local table_all_fuels = flow_modal_dialog["table_all_fuels"]
    table_all_fuels.clear()

    for fuel_id, fuel in pairs(global.all_fuels.fuels) do
        local button_fuel = table_all_fuels.add{type="sprite-button", name="fp_sprite-button_preferences_fuel_"
          .. fuel_id, sprite="item/" .. fuel.name, mouse_button_filter={"left"}}
          
        local tooltip = fuel.localised_name
        local preferred_fuel_id = get_preferences(player).preferred_fuel_id
        if preferred_fuel_id == fuel_id then
            button_fuel.style = "fp_button_icon_medium_green"
            tooltip = {"", tooltip, "\n", {"tooltip.selected"}}
        else 
            button_fuel.style = "fp_button_icon_medium_hidden"
        end
        button_fuel.tooltip = tooltip
    end

    -- Machine preferences
    local table_all_machines = flow_modal_dialog["table_all_machines"]
    table_all_machines.clear()

    for category_id, category in ipairs(global.all_machines.categories) do
        if #category.machines > 1 then
            table_all_machines.add{type="label", name="label_" .. category_id, caption="'" .. category.name .. "':    "}
            local table_machines = table_all_machines.add{type="table", name="table_machines_" .. category_id, column_count=8}
            for machine_id, machine in ipairs(category.machines) do
                local button_machine = table_machines.add{type="sprite-button", name="fp_sprite-button_preferences_machine_"
                  .. category_id .. "_" .. machine_id, sprite="entity/" .. machine.name, mouse_button_filter={"left"}}
                  
                local tooltip = machine.localised_name
                local default_machine_id = data_util.machines.get_default(player, category_id)
                if default_machine_id == machine_id then
                    button_machine.style = "fp_button_icon_medium_green"
                    tooltip = {"", tooltip, "\n", {"tooltip.selected"}}
                else 
                    button_machine.style = "fp_button_icon_medium_hidden"
                end
                button_machine.tooltip = tooltip
            end
        end
    end
end


-- Changes the default machine of the given category
function handle_preferences_machine_change(player, category_id, id)
    data_util.machines.set_default(player, category_id, id)
    refresh_preferences_dialog(player)
end

-- Changes the preferred belt
function handle_preferences_belt_change(player, id)
    get_preferences(player).preferred_belt_id = id
    refresh_preferences_dialog(player)
end

-- Changes the preferred fuel
function handle_preferences_fuel_change(player, id)
    get_preferences(player).preferred_fuel_id = id
    refresh_preferences_dialog(player)
end
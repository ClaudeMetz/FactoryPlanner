local general_preference_names = {"ignore_barreling_recipes", "ignore_recycling_recipes", "ingredient_satisfaction", "round_button_numbers", "prefer_matrix_solver"}
local production_preference_names = {"pollution", "line_comments"}

-- Handles populating the preferences dialog
function open_preferences_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"fp.preferences"}
    flow_modal_dialog.style.padding = 6

    -- Info
    local label_preferences_info = flow_modal_dialog.add{type="label", name="label_preferences_info", 
      caption={"fp.preferences_info"}}
    label_preferences_info.style.single_line = false
    label_preferences_info.style.bottom_margin = 4

    -- Alt action
    local table_alt_actions = flow_modal_dialog.add{type="table", name="table_alt_actions", column_count=2}
    table_alt_actions.style.horizontal_spacing = 16
    table_alt_actions.style.margin = {8, 0}
    table_alt_actions.add{type="label", name="label_alt_actions", caption={"", {"fp.preferences_alt_action"}, ":"}, style="fp_preferences_title_label", tooltip={"fp.preferences_alt_action_tt"}}

    local items = {}
    for action, index in pairs(global.alt_actions) do table.insert(items, {"fp.alt_action_" .. action}) end
    table_alt_actions.add{type="drop-down", name="fp_drop_down_alt_action", items=items, selected_index=1}

    -- General preferences
    flow_modal_dialog.add{type="label", name="label_general_info", caption={"", {"fp.preferences_title_general"}, ":"},
      style="fp_preferences_title_label", tooltip={"fp.preferences_title_general_tt"}}
    local table_general_prefs = flow_modal_dialog.add{type="table", name="table_general_preferences", column_count=1}
    table_general_prefs.style.top_margin = 2
    table_general_prefs.style.bottom_margin = 8
    table_general_prefs.style.left_margin = 16

    -- Creates the checkbox for a general preference 
    local function add_general_preference(name)
        table_general_prefs.add{type="checkbox", name=("fp_checkbox_preferences_" .. name), state=false,
          caption={"", " ", {"fp.preferences_" .. name}, " [img=info]"}, tooltip={"fp.preferences_" .. name .. "_tt"}}
    end

    for _, preference_name in ipairs(general_preference_names) do add_general_preference(preference_name) end

    -- Production table preferences
    flow_modal_dialog.add{type="label", name="label_production_info", caption={"", {"fp.preferences_title_production"}, ":"},
      style="fp_preferences_title_label", tooltip={"fp.preferences_title_production_tt"}}
    local table_production_prefs = flow_modal_dialog.add{type="table", name="table_production_preferences", column_count=1}
    table_production_prefs.style.top_margin = 2
    table_production_prefs.style.bottom_margin = 8
    table_production_prefs.style.left_margin = 16

    -- Creates the checkbox for a production preference 
    local function add_production_preference(name)
        table_production_prefs.add{type="checkbox", name=("fp_checkbox_production_preferences_" .. name), state=false,
          caption={"", " ", {"fp.production_preferences_" .. name}, " [img=info]"},
          tooltip={"fp.production_preferences_" .. name .. "_tt"}}
    end

    for _, preference_name in ipairs(production_preference_names) do add_production_preference(preference_name) end
    
    -- Prototype preferences
    local function add_prototype_preference(name)
        flow_modal_dialog.add{type="label", name=("label_".. name .. "_info"), caption={"", {"fp.preferences_title_" .. name}, ":"},
          style="fp_preferences_title_label", tooltip={"fp.preferences_title_" .. name .. "_tt"}}

        flow_modal_dialog.add{type="table", name=("table_all_" .. name), column_count=12, style="fp_preferences_table"}
    end

    local proto_preference_names = {"belts", "fuels"}
    -- Beacons are only needed when there is more than one beacon (ie. not vanilla)
    if #global.all_beacons.beacons > 1 then table.insert(proto_preference_names, "beacons") end
    for _, preference_name in ipairs(proto_preference_names) do add_prototype_preference(preference_name) end

    -- Machine preferences (needs custom construction as it is a 2d-prototype)
    flow_modal_dialog.add{type="label", name="label_machines_info", caption={"", {"fp.preferences_title_machines"}, ":"},
      style="fp_preferences_title_label", tooltip={"fp.preferences_title_machines_tt"}}

    local table_all_machines = flow_modal_dialog.add{type="table", name="table_all_machines", column_count=2}
    table_all_machines.style.top_margin = 4
    table_all_machines.style.left_padding = 6
    table_all_machines.style.bottom_padding = 4

    refresh_preferences_dialog(flow_modal_dialog.gui.player)
end


-- Creates the modal dialog to change your preferences
function refresh_preferences_dialog(player)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local preferences = get_preferences(player)

    -- Alt action
    local drop_down_alt_actions = flow_modal_dialog["table_alt_actions"]["fp_drop_down_alt_action"]
    drop_down_alt_actions.selected_index = global.alt_actions[preferences.alt_action]

    -- General preferences
    local table_general_prefs = flow_modal_dialog["table_general_preferences"]
    for _, preference_name in ipairs(general_preference_names) do
        table_general_prefs["fp_checkbox_preferences_" .. preference_name].state = preferences[preference_name]
    end

    -- Production preferences
    local table_production_prefs = flow_modal_dialog["table_production_preferences"]
    for _, preference_name in ipairs(production_preference_names) do
        table_production_prefs["fp_checkbox_production_preferences_" .. preference_name].state
          = preferences.optional_production_columns[preference_name]
    end

    -- Prototype preferences
    -- Refreshes the given prototype preference GUI, if it exists (for 1d-prototypes)
    local function refresh_prototype_preference(name)
        local pname = name .. "s"  -- 'plural_name'
        local table_all = flow_modal_dialog["table_all_" .. pname]
        if table_all == nil then return end  -- return if no preference for this prototype exist
        table_all.clear()

        for proto_id, proto in pairs(global["all_" .. pname][pname]) do
            local button = table_all.add{type="sprite-button", name="fp_sprite-button_preferences_" .. name .. "_"
              .. proto_id, sprite=proto.sprite, mouse_button_filter={"left"}}
            
            local tooltip = proto.localised_name
            if get_preferences(player)["preferred_" .. name] == proto then
                button.style = "fp_button_icon_medium_green"
                tooltip = {"", tooltip, " (", {"fp.selected"}, ")"}
            else 
                button.style = "fp_button_icon_medium_hidden"
            end
            button.tooltip = {"", tooltip, "\n", ui_util.attributes[name](proto)}
        end
    end

    local proto_preference_names = {"belt", "fuel", "beacon"}
    for _, preference_name in ipairs(proto_preference_names) do refresh_prototype_preference(preference_name) end

    -- Machine preferences (needs custom construction as it is a 2d-prototype)
    local table_all_machines = flow_modal_dialog["table_all_machines"]
    table_all_machines.clear()

    for category_id, category in ipairs(global.all_machines.categories) do
        if #category.machines > 1 then
            table_all_machines.add{type="label", name="label_" .. category_id, caption="'" .. category.name .. "':    "}
            local table_machines = table_all_machines.add{type="table", name="table_machines_" .. category_id, column_count=8}
            for machine_id, machine in ipairs(category.machines) do
                local button_machine = table_machines.add{type="sprite-button", name="fp_sprite-button_preferences_machine_"
                  .. category_id .. "_" .. machine_id, sprite=machine.sprite, mouse_button_filter={"left"}}
                  
                local tooltip = machine.localised_name
                if data_util.machine.get_default(player, category.name) == machine then
                    button_machine.style = "fp_button_icon_medium_green"
                    tooltip = {"", tooltip, " (", {"fp.selected"}, ")"}
                else 
                    button_machine.style = "fp_button_icon_medium_hidden"
                end
                button_machine.tooltip = {"", tooltip, "\n", ui_util.attributes.machine(machine)}
            end
        end
    end
end


-- Saves the given alt_action change
function handle_alt_action_change(player, selected_index)
    for action, index in pairs(global.alt_actions) do
        if selected_index == index then
            get_preferences(player).alt_action = action
            refresh_main_dialog(player)
            return
        end
    end
end

-- Saves the given general preference change
function handle_general_preference_change(player, radiobutton)
    local preference = string.gsub(radiobutton.name, "fp_checkbox_preferences_", "")
    get_preferences(player)[preference] = radiobutton.state
    
    if preference == "ingredient_satisfaction" and radiobutton.state == true then
        calculation.util.update_all_ingredient_satisfactions(player)
        refresh_production_pane(player)
    elseif preference == "ingredient_satisfaction" then
        refresh_production_pane(player)
    end
end

-- Saves the given production preference change
function handle_production_preference_change(player, radiobutton)
    local preference = string.gsub(radiobutton.name, "fp_checkbox_production_preferences_", "")
    get_preferences(player).optional_production_columns[preference] = radiobutton.state
    refresh_production_pane(player)
end

-- Changes the preferred prototype for the given prototype preference type
function handle_preferences_change(player, type, id)
    get_preferences(player)["preferred_" .. type] = global["all_" .. type .. "s"][type .. "s"][id]
    refresh_preferences_dialog(player)
    if type == "belt" then refresh_production_pane(player) end
end

-- Changes the default machine of the given category
function handle_preferences_machine_change(player, category_id, id)
    data_util.machine.set_default(player, category_id, id)
    refresh_preferences_dialog(player)
end
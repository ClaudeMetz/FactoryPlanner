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

    -- Creates the checkbox for a general preference 
    local function add_general_preference(name)
        table_general_prefs.add{type="checkbox", name=("fp_checkbox_preferences_" .. name), state=false,
          caption={"", " ", {"checkbox.preferences_" .. name}, " [img=info]"}, tooltip={"tooltip.preferences_" .. name}}
    end

    local preference_names = {"ignore_barreling_recipes", "enable_recipe_comments"}
    for _, preference_name in ipairs(preference_names) do add_general_preference(preference_name) end


    -- Prototype preferences
    local function add_prototype_preference(name)
        flow_modal_dialog.add{type="label", name=("label_".. name .. "_info"), caption={"", {"label.preferences_title_" .. name}, ":"},
          style="fp_preferences_title_label", tooltip={"tooltip.preferences_title_" .. name}}

        flow_modal_dialog.add{type="table", name=("table_all_" .. name), column_count=12, style="fp_preferences_table"}
    end

    local proto_preference_names = {"belts", "fuels"}
    -- Beacons are only needed when there is more than one beacon (ie. not vanilla)
    if #global.all_beacons.beacons > 1 then table.insert(proto_preference_names, "beacons") end
    for _, preference_name in ipairs(proto_preference_names) do add_prototype_preference(preference_name) end

    -- Machine preferences (needs custom construction as it is a 2d-prototype)
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
    local preference_names = {"ignore_barreling_recipes", "enable_recipe_comments"}
    for _, preference_name in ipairs(preference_names) do
        table_general_prefs["fp_checkbox_preferences_" .. preference_name].state = preferences[preference_name]
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
                tooltip = {"", tooltip, " (", {"tooltip.selected"}, ")"}
            else 
                button.style = "fp_button_icon_medium_hidden"
            end
            button.tooltip = {"", tooltip, "\n", ui_util["generate_" .. name .. "_attributes_tooltip"](proto)}
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
                  .. category_id .. "_" .. machine_id, sprite="entity/" .. machine.name, mouse_button_filter={"left"}}
                  
                local tooltip = machine.localised_name
                if data_util.machine.get_default(player, category) == machine then
                    button_machine.style = "fp_button_icon_medium_green"
                    tooltip = {"", tooltip, " (", {"tooltip.selected"}, ")"}
                else 
                    button_machine.style = "fp_button_icon_medium_hidden"
                end
                button_machine.tooltip = {"", tooltip, "\n", ui_util.generate_machine_attributes_tooltip(machine)}
            end
        end
    end
end


-- Changes the preferred prototype for the given prototype preference type
function handle_preferences_change(player, type, id)
    get_preferences(player)["preferred_" .. type] = global["all_" .. type .. "s"][type .. "s"][id]
    refresh_preferences_dialog(player)
end

-- Changes the default machine of the given category
function handle_preferences_machine_change(player, category_id, id)
    data_util.machine.set_default(player, category_id, id)
    refresh_preferences_dialog(player)
end
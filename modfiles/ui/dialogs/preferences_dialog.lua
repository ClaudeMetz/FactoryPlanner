local general_preference_names = {"ignore_barreling_recipes", "ignore_recycling_recipes", "ingredient_satisfaction", "round_button_numbers"}
local production_preference_names = {"pollution", "line_comments"}
local prototype_preference_names = {"belts", "beacons", "fuels", "machines"}

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


    -- General+Production-preferences
    local function add_checkbox_preferences(type, preference_names)
        flow_modal_dialog.add{type="label", name="label_" .. type .. "_info", 
          caption={"", {"fp.preferences_title_" .. type}, ":"}, style="fp_preferences_title_label",
          tooltip={"fp.preferences_title_" .. type .. "_tt"}}
        local table_prefs = flow_modal_dialog.add{type="table", name="table_" .. type .. "_preferences", column_count=1}
        table_prefs.style.margin = {2, 0, 8, 16}

        for _, name in ipairs(preference_names) do
            table_prefs.add{type="checkbox", name=("fp_checkbox_" .. type .. "_preferences_" .. name), state=false,
              caption={"", " ", {"fp." .. type .. "_preferences_" .. name}, " [img=info]"},
              tooltip={"fp." .. type .. "_preferences_" .. name .. "_tt"}}
        end
    end

    add_checkbox_preferences("general", general_preference_names)
    add_checkbox_preferences("production", production_preference_names)


    -- Module/Beacon defaults
    flow_modal_dialog.add{type="label", name="label_module_beacon_defaults", 
      caption={"", {"fp.preferences_title_mb_defaults"}, ":"}, style="fp_preferences_title_label",
      tooltip={"fp.preferences_title_mb_defaults_tt"}}
    local flow_mb_defaults = flow_modal_dialog.add{type="flow", name="flow_module_beacon_defaults",
      direction="horizontal"}
    flow_mb_defaults.style.margin = {2, 6, 8, 16}
    flow_mb_defaults.style.vertical_align = "center"

    local function add_mb_default(kind)
        flow_mb_defaults.add{type="label", caption={"", {"fp.c" .. kind}, ": "}}
        local choose_elem_button = flow_mb_defaults.add{type="choose-elem-button", elem_type="item",
          name="fp_choose-elem-button_default_" .. kind, style="fp_sprite-button_choose_elem"}
        choose_elem_button.elem_filters = {{filter="type", type="module"}, 
          {filter="flag", flag="hidden", mode="and", invert=true}}
        choose_elem_button.style.right_margin = 12
    end

    add_mb_default("module")
    add_mb_default("beacon")

    flow_mb_defaults.add{type="label", caption={"", {"fp.beacon_count"}, ": "}}
    local textfield_beacon_count = flow_mb_defaults.add{type="textfield", name="fp_textfield_default_beacon_count"}
    ui_util.setup_numeric_textfield(textfield_beacon_count, true, false)
    textfield_beacon_count.style.width = 42
    

    -- Prototype preferences
    local function add_prototype_preference(type)
        local flow_proto_pref = flow_modal_dialog.add{type="flow", name="flow_prototype_preference_" .. type,
          direction="vertical"}
        flow_proto_pref.add{type="label", name=("label_" .. type .. "_info"),
          caption={"", {"fp.preferences_title_" .. type}, ":"}, style="fp_preferences_title_label",
          tooltip={"fp.preferences_title_" .. type .. "_tt"}}
        local flow_proto = flow_proto_pref.add{type="flow", name="flow_prototype_preferences", direction="vertical"}
        flow_proto.style.margin = {4, 8, 8, 16}
    end

    for _, preference_name in ipairs(prototype_preference_names) do
        add_prototype_preference(preference_name)
    end


    refresh_preferences_dialog(flow_modal_dialog.gui.player)

    -- Not sure why this is necessary, but it goes wonky otherwise
    -- This is only been necessary when a choose-elem-button is present, weirdly
    flow_modal_dialog.parent.force_auto_center()
end


-- Creates the modal dialog to change your preferences
function refresh_preferences_dialog(player)
    local flow_modal_dialog = ui_util.find_modal_dialog(player)["flow_modal_dialog"]
    local preferences = get_preferences(player)


    -- Alt action
    local drop_down_alt_actions = flow_modal_dialog["table_alt_actions"]["fp_drop_down_alt_action"]
    drop_down_alt_actions.selected_index = global.alt_actions[preferences.alt_action]


    -- General+Production preferences
    local function refresh_checkbox_preferences(type, preference_names, pref_table)
        local table_prefs = flow_modal_dialog["table_" .. type .. "_preferences"]
        for _, name in ipairs(preference_names) do
            table_prefs["fp_checkbox_" .. type .. "_preferences_" .. name].state = pref_table[name]
        end
    end

    refresh_checkbox_preferences("general", general_preference_names, preferences)
    refresh_checkbox_preferences("production", production_preference_names, preferences.optional_production_columns)


    -- Module/Beacon defaults preferences
    local flow_mb_defaults = flow_modal_dialog["flow_module_beacon_defaults"]
    local mb_defaults = preferences.mb_defaults
    flow_mb_defaults["fp_choose-elem-button_default_module"].elem_value =
      (mb_defaults.module) and mb_defaults.module.name or nil
    flow_mb_defaults["fp_choose-elem-button_default_beacon"].elem_value =
      (mb_defaults.beacon) and mb_defaults.beacon.name or nil
    flow_mb_defaults["fp_textfield_default_beacon_count"].text = mb_defaults.beacon_count or ""


    -- Prototype preferences
    local function refresh_prototype_preference(type)
        local default_prototypes = preferences.default_prototypes[type]
        local flow_proto_pref = flow_modal_dialog["flow_prototype_preference_" .. type]["flow_prototype_preferences"]
        flow_proto_pref.clear()

        if default_prototypes.structure_type == "simple" then
            local all_prototypes = global["all_" .. type][type]
            flow_proto_pref.parent.visible = (table_size(all_prototypes) > 1)

            local default_prototype = default_prototypes.prototype
            create_default_prototype_category(flow_proto_pref, type, all_prototypes, default_prototype, nil, 12)

        else  -- structure_type == "complex"
            local all_categories = global["all_" .. type].categories

            local table_all_categories = flow_proto_pref.add{type="table", name="table_all_" .. type .. "_categories",
              column_count=2}
            table_all_categories.style.horizontal_spacing = 16

            for category_id, category in ipairs(all_categories) do
                local all_prototypes = category[type]

                if table_size(all_prototypes) > 1 then
                    table_all_categories.add{type="label", name="label_" .. category_id, 
                      caption="'" .. category.name .. "':"}
                    
                    local default_prototype = default_prototypes.prototypes[category_id]
                    create_default_prototype_category(table_all_categories, type, all_prototypes,
                      default_prototype, category_id, 8)
                end
            end           

        end
    end

    for _, preference_name in ipairs(prototype_preference_names) do
        refresh_prototype_preference(preference_name)
    end
end

-- Creates the flow for the given category of prototypes
function create_default_prototype_category(flow, type, all_prototypes, default_prototype, category_id, column_count)
    local category_addendum = (category_id ~= nil) and ("_" .. category_id) or ""
    local table_prototypes = flow.add{type="table", name=("table_prototypes_" .. type .. category_addendum),
      column_count=column_count}
    table_prototypes.style.bottom_margin = 6

    for proto_id, proto in ipairs(all_prototypes) do
        local button = table_prototypes.add{type="sprite-button", name="fp_sprite-button_preferences_" .. type .. "_"
          .. proto_id .. category_addendum, sprite=proto.sprite, mouse_button_filter={"left"}}
        
        local tooltip = proto.localised_name
        if default_prototype.name == proto.name then
            button.style = "fp_button_icon_medium_green"
            tooltip = {"", tooltip, " (", {"fp.selected"}, ")"}
        else 
            button.style = "fp_button_icon_medium_hidden"
        end
        button.tooltip = {"", tooltip, "\n", ui_util.attributes[type:sub(1, -2)](proto)}
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


-- Saves the given general- or production-preference change
function handle_checkbox_preference_change(player, type, preference, state)
    local preferences = get_preferences(player)
    
    if type == "general" then
        preferences[preference] = state
    
        if preference == "ingredient_satisfaction" or preference == "round_button_numbers" then
            if state == true then calculation.util.update_all_ingredient_satisfactions(player) end
            refresh_production_pane(player)
        end
    else  -- type == "production"
        preferences.optional_production_columns[preference] = state
        refresh_production_pane(player)
    end
end


-- Saves changes to the module/beacon defaults
function handle_mb_defaults_change(player, button)
    local mb_defaults = get_preferences(player).mb_defaults
    local type = string.gsub(button.name, "fp_choose%-elem%-button_default_", "")
    local module_name = button.elem_value

    if module_name == nil then
        mb_defaults[type] = nil
    else
        -- Find the appropriate prototype from the list by its name
        for _, category in pairs(global.all_modules.categories) do
            for _, module_proto in pairs(category.modules) do
                if module_proto.name == module_name then
                    mb_defaults[type] = module_proto
                    return
                end
            end
        end
    end
end


-- Persists changes to any default prototype and refreshes appropriately
function handle_prototype_preference_change(player, type, prototype_id, category_id)
    prototyper.defaults.set(player, type, prototype_id, category_id)
    refresh_preferences_dialog(player)
    if type == "belts" then refresh_production_pane(player) end
end
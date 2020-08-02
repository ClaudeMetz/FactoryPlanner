preferences_dialog = {}

local prototype_preference_names = {"belts", "beacons", "fuels", "machines"}

-- ** LOCAL UTIL **
local function add_preference_box(ui_elements, type)
    local bordered_frame = ui_elements.content_frame.add{type="frame", direction="vertical", style="bordered_frame"}
    bordered_frame.style.horizontally_stretchable = true
    bordered_frame.style.top_margin = 4
    ui_elements[type .. "_box"] = bordered_frame

    local caption = {"fp.info_label", {"fp.preference_".. type .. "_title"}}
    local tooltip = {"fp.preference_".. type .. "_title_tt"}
    bordered_frame.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}

    return bordered_frame
end

local preference_structures = {}

function preference_structures.checkboxes(preferences, ui_elements, type, preference_names)
    local preference_box = add_preference_box(ui_elements, type)
    local flow_checkboxes = preference_box.add{type="flow", direction="vertical"}

    for _, pref_name in ipairs(preference_names) do
        local identifier = type .. "_" .. pref_name
        local caption = {"fp.info_label", {"fp.preference_" .. identifier}}
        local tooltip ={"fp.preference_" .. identifier .. "_tt"}
        flow_checkboxes.add{type="checkbox", name=("fp_checkbox_preference_" .. identifier),
          state=preferences[pref_name], caption=caption, tooltip=tooltip}
    end
end


-- Creates the flow for the given category of prototypes
local function create_default_prototype_category(flow, type, all_prototypes, default_prototype, category_id, column_count)
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

-- Creates the modal dialog to change your preferences
local function refresh_preferences_dialog(player)
    local flow_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
    local preferences = get_preferences(player)

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
            flow_proto_pref.parent.visible = (#all_prototypes > 1)

            local default_prototype = default_prototypes.prototype
            create_default_prototype_category(flow_proto_pref, type, all_prototypes, default_prototype, nil, 12)

        else  -- structure_type == "complex"
            local all_categories = global["all_" .. type].categories

            local table_all_categories = flow_proto_pref.add{type="table", name="table_all_" .. type .. "_categories",
              column_count=2}
            table_all_categories.style.horizontal_spacing = 16

            for category_id, category in ipairs(all_categories) do
                local all_prototypes = category[type]

                if #all_prototypes > 1 then
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


local function handle_checkbox_preference_change(player, element)
    local type = cutil.split(element.name, "_")[4]
    local preference_name = string.gsub(element.name, "fp_checkbox_preference_" .. type .. "_", "")

    data_util.get("preferences", player)[preference_name] = element.state
    local refresh = data_util.get("modal_data", player).refresh

    if type == "production" or preference_name == "round_button_numbers" then
        refresh.production_table = true
    end

    if preference_name == "ingredient_satisfaction" then
        refresh.production_table = true
        -- Only recalculate if the satisfaction data will actually be shown now
        refresh.ingredient_satisfaction = (element.state)
    end
end


-- ** TOP LEVEL **
preferences_dialog.dialog_settings = (function(_) return {
    caption = {"fp.preferences"}
} end)

preferences_dialog.events = {
    on_gui_checked_state_changed = {
        {
            pattern = "^fp_checkbox_preference_[a-z]+_[a-z_]+$",
            handler = (function(player, element)
                handle_checkbox_preference_change(player, element)
            end)
        }
    }
}

function preferences_dialog.open(player, _, modal_data)
    local preferences = data_util.get("preferences", player)
    modal_data.refresh = {}

    local ui_elements = modal_data.ui_elements
    ui_elements.content_frame = ui_elements.flow_modal_dialog.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}

    local bordered_frame = ui_elements.content_frame.add{type="frame", direction="vertical", style="bordered_frame"}
    local label_preferences_info = bordered_frame.add{type="label", caption={"fp.preferences_info"}}
    label_preferences_info.style.single_line = false

    local general_preference_names = {"ignore_barreling_recipes", "ignore_recycling_recipes",
       "ingredient_satisfaction", "round_button_numbers"}
    preference_structures.checkboxes(preferences, ui_elements, "general", general_preference_names)

    local production_preference_names = {"pollution_column", "line_comment_column"}
    preference_structures.checkboxes(preferences, ui_elements, "production", production_preference_names)




    if true then return end


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


    refresh_preferences_dialog(player)

    -- Not sure why this is necessary, but it goes wonky otherwise
    -- This is only been necessary when a choose-elem-button is present, weirdly
    flow_modal_dialog.parent.force_auto_center()
end

function preferences_dialog.close(player, _, _)
    local refresh = data_util.get("modal_data", player).refresh

    if refresh.ingredient_satisfaction then
        local player_table = get_table(player)
        Factory.update_ingredient_satisfactions(player_table.factory)
        Factory.update_ingredient_satisfactions(player_table.archive)
    end

    if refresh.production_table then production_table.refresh(player) end
end


-- Saves changes to the module/beacon defaults
function preferences_dialog.handle_mb_defaults_change(player, button)
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
function preferences_dialog.handle_prototype_change(player, type, prototype_id, category_id, alt)
    prototyper.defaults.set(player, type, prototype_id, category_id)

    -- If this was an alt-click, set this prototype on every category that also has it
    if alt and category_id ~= nil then
        local prototype = prototyper.defaults.get(player, type, category_id)
        for secondary_category_id, category in pairs(global["all_" .. type].categories) do
            local secondary_prototype_id = category.map[prototype.name]
            if secondary_prototype_id ~= nil then
                prototyper.defaults.set(player, type, secondary_prototype_id, secondary_category_id)
            end
        end
    end

    refresh_preferences_dialog(player)
    if type == "belts" then main_dialog.refresh(player) end
end
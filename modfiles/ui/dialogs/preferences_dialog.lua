preferences_dialog = {}

-- ** LOCAL UTIL **
local function add_preference_box(content_frame, type)
    local bordered_frame = content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}

    local caption = {"fp.info_label", {"fp.preference_".. type .. "_title"}}
    local tooltip = {"fp.preference_".. type .. "_title_tt"}
    bordered_frame.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}

    return bordered_frame
end

local function refresh_defaults_table(player, modal_elements, type, category_id)
    local table_prototypes, all_prototypes, category_addendum

    if not category_id then
        table_prototypes = modal_elements[type]
        all_prototypes = global["all_" .. type][type]
        category_addendum = ""
    else
        table_prototypes = modal_elements[type][category_id]
        all_prototypes = global["all_" .. type].categories[category_id][type]
        category_addendum = ("_" .. category_id)
    end

    table_prototypes.clear()
    local default_proto = prototyper.defaults.get(player, type, category_id)

    for prototype_id, prototype in ipairs(all_prototypes) do
        local selected = (default_proto.id == prototype_id)
        local style = (selected) and "flib_slot_button_green_small" or "flib_slot_button_default_small"
        local first_line = (selected) and {"fp.annotated_title", prototype.localised_name, {"fp.selected"}}
            or prototype.localised_name
        local tooltip = {"", first_line, "\n", data_util.get_attributes(type, prototype)}

        table_prototypes.add{type="sprite-button", sprite=prototype.sprite, tooltip=tooltip,
          name="fp_sprite-button_preference_default_" .. type .. "_" .. prototype_id .. category_addendum,
          style=style, mouse_button_filter={"left"}}
    end
end


local preference_structures = {}

function preference_structures.checkboxes(preferences, content_frame, type, preference_names)
    local preference_box = add_preference_box(content_frame, type)
    local flow_checkboxes = preference_box.add{type="flow", direction="vertical"}

    for _, pref_name in ipairs(preference_names) do
        local identifier = type .. "_" .. pref_name
        local caption = {"fp.info_label", {"fp.preference_" .. identifier}}
        local tooltip ={"fp.preference_" .. identifier .. "_tt"}
        flow_checkboxes.add{type="checkbox", name=("fp_checkbox_preference_" .. identifier),
          state=preferences[pref_name], caption=caption, tooltip=tooltip}
    end
end

function preference_structures.mb_defaults(preferences, content_frame)
    local mb_defaults = preferences.mb_defaults
    local preference_box = add_preference_box(content_frame, "mb_defaults")

    local function add_mb_default_button(parent_flow, type)
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.vertical_align = "center"
        flow.style.horizontal_spacing = 8

        flow.add{type="label", caption={"fp.info_label", {"fp.preference_mb_default_" .. type}},
          tooltip={"fp.preference_mb_default_" .. type .. "_tt"}}
        local item = (mb_defaults[type] ~= nil) and mb_defaults[type].name or nil
        flow.add{type="choose-elem-button", elem_type="item", item=item,
          name="fp_choose-elem-button_mb_default_" .. type, style="fp_sprite-button_inset_tiny",
          elem_filters={{filter="type", type="module"}, {filter="flag", flag="hidden", mode="and", invert=true}}}
    end

    local table_mb_defaults = preference_box.add{type="table", column_count=3}
    table_mb_defaults.style.horizontal_spacing = 18
    -- Table alignment is so stupid
    table_mb_defaults.style.column_alignments[1] = "left"
    table_mb_defaults.style.column_alignments[2] = "right"
    table_mb_defaults.style.column_alignments[3] = "right"

    table_mb_defaults.add{type="label", caption={"fp.key_title", {"fp.pu_machine", 1}}}
    add_mb_default_button(table_mb_defaults, "machine")
    add_mb_default_button(table_mb_defaults, "machine_secondary")

    table_mb_defaults.add{type="label", caption={"fp.key_title", {"fp.pu_beacon", 1}}}
    add_mb_default_button(table_mb_defaults, "beacon")

    local beacon_amount_flow = table_mb_defaults.add{type="flow", direction="horizontal"}
    beacon_amount_flow.style.vertical_align = "center"
    beacon_amount_flow.style.horizontal_spacing = 8

    beacon_amount_flow.add{type="label", caption={"fp.info_label", {"fp.preference_mb_default_beacon_amount"}},
      tooltip={"fp.preference_mb_default_beacon_amount_tt"}}

    local textfield_amount = beacon_amount_flow.add{type="textfield", name="fp_textfield_mb_default_beacon_amount",
      text=tostring(mb_defaults.beacon_count or "")}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    textfield_amount.style.width = 42
end

function preference_structures.prototypes(player, content_frame, modal_elements, type)
    local preference_box = add_preference_box(content_frame, ("default_" .. type))
    local table_prototypes = preference_box.add{type="table", column_count=3}
    table_prototypes.style.horizontal_spacing = 20
    table_prototypes.style.vertical_spacing = 8
    table_prototypes.style.top_margin = 4

    local function add_defaults_table(column_count, category_id)
        local frame = table_prototypes.add{type="frame", direction="horizontal", style="fp_frame_deep_slots_small"}
        frame.style.right_margin = 6
        local table = frame.add{type="table", column_count=column_count, style="filter_slot_table"}

        if category_id then
            modal_elements[type] = modal_elements[type] or {}
            modal_elements[type][category_id] = table
        else
            modal_elements[type] = table
        end
    end

    local preferences = data_util.get("preferences", player)
    local default_prototypes = preferences.default_prototypes[type]
    if default_prototypes.structure_type == "simple" then
        local all_prototypes = global["all_" .. type][type]
        if #all_prototypes < 2 then preference_box.visible = false; return end

        add_defaults_table(8, nil)
        refresh_defaults_table(player, modal_elements, type, nil)

    else  -- structure_type == "complex"
        local all_categories = global["all_" .. type].categories
        if #all_categories == 0 then preference_box.visible = false; return end

        local any_category_visible = false
        for category_id, category in ipairs(all_categories) do
            local all_prototypes = category[type]

            if #all_prototypes > 1 then
                any_category_visible = true

                table_prototypes.add{type="label", caption={"fp.quoted_title", category.name}}
                table_prototypes.add{type="empty-widget", style="flib_horizontal_pusher"}

                add_defaults_table(8, category_id)
                refresh_defaults_table(player, modal_elements, type, category_id)
            end
        end
        if not any_category_visible then preference_box.visible = false end
    end
end


local function handle_checkbox_preference_change(player, element)
    local type = split_string(element.name, "_")[4]
    local preference_name = string.gsub(element.name, "fp_checkbox_preference_" .. type .. "_", "")

    data_util.get("preferences", player)[preference_name] = element.state
    local refresh = data_util.get("modal_data", player).refresh

    if type == "production" or preference_name == "round_button_numbers" then
        refresh.production_table = true
    end

    if preference_name == "toggle_column" then
        refresh.calculations = true
    end

    if preference_name == "ingredient_satisfaction" then
        -- Only recalculate if the satisfaction data will actually be shown now
        refresh.update_ingredient_satisfaction = (element.state)
        refresh.production_table = true  -- always refresh the production_table
    end
end

local function handle_mb_default_change(player, element)
    local mb_defaults = data_util.get("preferences", player).mb_defaults
    local type = string.gsub(element.name, "fp_choose%-elem%-button_mb_default_", "")
    local module_name = element.elem_value

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

local function handle_default_prototype_change(player, element, metadata)
    local split_name = split_string(element.name, "_")
    local type, prototype_id, category_id = split_name[5], split_name[6], split_name[7]

    local modal_data = data_util.get("modal_data", player)
    if type == "belts" then modal_data.refresh.view_state = true end

    prototyper.defaults.set(player, type, prototype_id, category_id)
    refresh_defaults_table(player, modal_data.modal_elements, type, category_id)

    -- If this was an alt-click, set this prototype on every category that also has it
    if metadata.alt and type == "machines" then
        local new_default_prototype = prototyper.defaults.get(player, type, category_id)

        for secondary_category_id, category in pairs(global["all_" .. type].categories) do
            local secondary_prototype_id = category.map[new_default_prototype.name]

            if secondary_prototype_id ~= nil then
                prototyper.defaults.set(player, type, secondary_prototype_id, secondary_category_id)
                refresh_defaults_table(player, modal_data.modal_elements, type, secondary_category_id)
            end
        end
    end
end


-- ** TOP LEVEL **
preferences_dialog.dialog_settings = (function(_) return {
    caption = {"fp.preferences"},
    create_content_frame = false,
    force_auto_center = true
} end)

function preferences_dialog.open(player, modal_data)
    local preferences = data_util.get("preferences", player)
    local modal_elements = modal_data.modal_elements
    modal_data.refresh = {}

    local flow_content = modal_elements.dialog_flow.add{type="flow", direction="horizontal"}
    flow_content.style.horizontal_spacing = 12
    local main_dialog_dimensions = data_util.get("ui_state", player).main_dialog_dimensions
    flow_content.style.maximal_height = main_dialog_dimensions.height * 0.75

    local function add_content_frame()
        local content_frame = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}
        content_frame.style.vertically_stretchable = true

        return content_frame.add{type="scroll-pane", style="flib_naked_scroll_pane"}
    end

    local left_content_frame = add_content_frame()

    local bordered_frame = left_content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    local label_preferences_info = bordered_frame.add{type="label", caption={"fp.preferences_info"}}
    label_preferences_info.style.single_line = false

    local general_preference_names = {"ignore_barreling_recipes", "ignore_recycling_recipes",
      "ingredient_satisfaction", "round_button_numbers"}
    preference_structures.checkboxes(preferences, left_content_frame, "general", general_preference_names)

    local production_preference_names = {"toggle_column", "pollution_column", "line_comment_column", "done_column"}
    preference_structures.checkboxes(preferences, left_content_frame, "production", production_preference_names)

    preference_structures.mb_defaults(preferences, left_content_frame)

    preference_structures.prototypes(player, left_content_frame, modal_elements, "belts")
    preference_structures.prototypes(player, left_content_frame, modal_elements, "beacons")

    local right_content_frame = add_content_frame()

    preference_structures.prototypes(player, right_content_frame, modal_elements, "fuels")
    preference_structures.prototypes(player, right_content_frame, modal_elements, "machines")
end

function preferences_dialog.close(player, _)
    -- We refresh all these things only when closing to avoid duplicate refreshes
    local refresh = data_util.get("modal_data", player).refresh

    if refresh.update_ingredient_satisfaction then
        local player_table = data_util.get("table", player)
        Factory.update_ingredient_satisfactions(player_table.factory)
        Factory.update_ingredient_satisfactions(player_table.archive)
    end

    local context_to_refresh = nil  -- don't refresh by default

    -- The order of these matters, they go from smallest context to biggest
    if refresh.production_table then
        context_to_refresh = "production_table"
    end

    if refresh.view_state then
        -- Rebuilding state requires every button that shows item amounts to refresh
        view_state.rebuild_state(player)
        context_to_refresh = "production"
    end

    if refresh.calculations then
        local context = data_util.get("context", player)
        calculation.update(player, context.subfactory)
        context_to_refresh = "subfactory"
    end

    if context_to_refresh then main_dialog.refresh(player, context_to_refresh) end
end


-- ** EVENTS **
preferences_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_preference_default_[a-z]+_%d+_?%d*$",
            handler = handle_default_prototype_change
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_mb_default_beacon_amount",
            handler = (function(player, element)
                local mb_defaults = data_util.get("preferences", player).mb_defaults
                mb_defaults.beacon_count = tonumber(element.text)
            end)
        }
    },
    on_gui_checked_state_changed = {
        {
            pattern = "^fp_checkbox_preference_[a-z]+_[a-z_]+$",
            handler = handle_checkbox_preference_change
        }
    },
    on_gui_elem_changed = {
        {
            pattern = "^fp_choose%-elem%-button_mb_default_[a-z_]+$",
            handler = handle_mb_default_change
        }
    }
}

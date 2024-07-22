-- ** LOCAL UTIL **
local function add_preference_box(content_frame, type)
    local bordered_frame = content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    local title_flow = bordered_frame.add{type="flow", direction="horizontal", name="title_flow"}
    title_flow.style.vertical_align = "center"

    local caption = {"fp.info_label", {"fp.preference_".. type .. "_title"}}
    local tooltip = {"fp.preference_".. type .. "_title_tt"}
    title_flow.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}

    return bordered_frame
end

local function refresh_defaults_table(player, modal_elements, type, category_id)
    local table_prototypes, prototypes

    if not category_id then
        table_prototypes = modal_elements[type]
        prototypes = global.prototypes[type]
    else
        table_prototypes = modal_elements[type][category_id]
        prototypes = global.prototypes[type][category_id].members
    end

    table_prototypes.clear()
    local default_proto = prototyper.defaults.get(player, type, category_id)

    for prototype_id, prototype in ipairs(prototypes) do
        local selected = (default_proto.id == prototype_id)
        local style = (selected) and "flib_slot_button_green_small" or "flib_slot_button_default_small"
        local first_line = (selected) and {"fp.tt_title_with_note", prototype.localised_name, {"fp.selected"}}
            or {"fp.tt_title", prototype.localised_name}
        local tooltip = {"", first_line, "\n", prototyper.util.get_attributes(prototype)}

        table_prototypes.add{type="sprite-button", sprite=prototype.sprite, tooltip=tooltip, style=style,
            tags={mod="fp", on_gui_click="select_preference_default", type=type, prototype_id=prototype_id,
            category_id=category_id}, mouse_button_filter={"left"}}
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
        flow_checkboxes.add{type="checkbox", state=preferences[pref_name], caption=caption, tooltip=tooltip,
            tags={mod="fp", on_gui_checked_state_changed="toggle_preference", type=type, name=pref_name}}
    end

    return preference_box
end

function preference_structures.dropdowns(preferences, parent_flow)
    local function add_dropdown(name, items, selected_index)
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.top_margin = 4

        flow.add{type="label", caption={"fp.info_label", {"fp.preference_dropdown_" .. name}},
            tooltip={"fp.preference_dropdown_" .. name .. "_tt"}}
        flow.add{type="empty-widget", style="flib_horizontal_pusher"}
        flow.add{type="drop-down", items=items, selected_index=selected_index, style="fp_drop-down_slim",
            tags={mod="fp", on_gui_selection_state_changed="choose_preference", name=name}}
    end


    local width_items, width_index = {}, nil
    for index, value in pairs(PRODUCTS_PER_ROW_OPTIONS) do
        width_items[index] = {"", value .. " ", {"fp.pl_product", 2}}
        if value == preferences.products_per_row then width_index = index end
    end
    add_dropdown("products_per_row", width_items, width_index)

    local height_items, height_index = {}, nil
    for index, value in pairs(FACTORY_LIST_ROWS_OPTIONS) do
        height_items[index] = {"", value .. " ", {"fp.rows"}}
        if value == preferences.factory_list_rows then height_index = index end
    end
    add_dropdown("factory_list_rows", height_items, height_index)

    local timescale_items, timescale_index = {}, nil
    for value, name in pairs(TIMESCALE_MAP) do
        table.insert(timescale_items, {"fp.per_timescale", {"fp." .. name}})
        if value == preferences.default_timescale then timescale_index = table_size(timescale_items) end
    end
    add_dropdown("default_timescale", timescale_items, timescale_index)
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
        flow.add{type="choose-elem-button", elem_type="item", item=item, style="fp_sprite-button_inset",
            elem_filters={{filter="type", type="module"}--[[ , {filter="hidden", mode="and", invert=true} ]]},
            tags={mod="fp", on_gui_elem_changed="change_mb_default", type=type}}
    end

    local table_mb_defaults = preference_box.add{type="table", column_count=3}
    table_mb_defaults.style.horizontal_spacing = 18
    -- Table alignment is so stupid
    table_mb_defaults.style.column_alignments[1] = "left"
    table_mb_defaults.style.column_alignments[2] = "right"
    table_mb_defaults.style.column_alignments[3] = "right"

    table_mb_defaults.add{type="label", caption={"fp.pu_machine", 1}, style="semibold_label"}
    add_mb_default_button(table_mb_defaults, "machine")
    add_mb_default_button(table_mb_defaults, "machine_secondary")

    table_mb_defaults.add{type="label", caption={"fp.pu_beacon", 1}, style="semibold_label"}
    add_mb_default_button(table_mb_defaults, "beacon")

    local beacon_amount_flow = table_mb_defaults.add{type="flow", direction="horizontal"}
    beacon_amount_flow.style.vertical_align = "center"
    beacon_amount_flow.style.horizontal_spacing = 8

    beacon_amount_flow.add{type="label", caption={"fp.info_label", {"fp.preference_mb_default_beacon_amount"}},
        tooltip={"fp.preference_mb_default_beacon_amount_tt"}}

    local textfield_amount = beacon_amount_flow.add{type="textfield", text=mb_defaults.beacon_count,
        tags={mod="fp", on_gui_text_changed="mb_default_beacon_amount"}}
    util.gui.setup_numeric_textfield(textfield_amount, false, false)
    textfield_amount.style.width = 42
end

function preference_structures.prototypes(player, content_frame, modal_elements, type)
    local preference_box = add_preference_box(content_frame, ("default_" .. type))
    local table_prototypes = preference_box.add{type="table", column_count=3}
    table_prototypes.style.horizontal_spacing = 20
    table_prototypes.style.vertical_spacing = 8
    table_prototypes.style.top_margin = 4

    local function add_defaults_table(column_count, category_id)
        local frame = table_prototypes.add{type="frame", direction="horizontal", style="fp_frame_light_slots_small"}
        local table = frame.add{type="table", column_count=column_count, style="fp_table_slots_small"}

        if category_id then
            modal_elements[type] = modal_elements[type] or {}
            modal_elements[type][category_id] = table
        else
            modal_elements[type] = table
        end
    end

    if not prototyper.data_types[type] then
        local prototypes = global.prototypes[type]
        if #prototypes < 2 then preference_box.visible = false; goto skip end

        add_defaults_table(10, nil)
        refresh_defaults_table(player, modal_elements, type, nil)
    else
        local categories = global.prototypes[type]
        if not next(categories) then preference_box.visible = false; goto skip end

        local any_category_visible = false
        for category_id, category in ipairs(categories) do
            local prototypes = category.members

            if #prototypes > 1 then
                any_category_visible = true

                local category_caption = {"?", {type:sub(1, -2) .. "-category-name." .. category.name},
                    "'" .. category.name .. "'"}
                table_prototypes.add{type="label", caption=category_caption}
                table_prototypes.add{type="empty-widget", style="flib_horizontal_pusher"}

                add_defaults_table(6, category_id)
                refresh_defaults_table(player, modal_elements, type, category_id)
            end
        end
        if not any_category_visible then preference_box.visible = false end
    end

    :: skip ::
    return preference_box
end


local function handle_checkbox_preference_change(player, tags, event)
    local preference_name = tags.name
    util.globals.preferences(player)[preference_name] = event.element.state

    if tags.type == "production" or preference_name == "round_button_numbers"
            or preference_name == "show_floor_items" or preference_name == "fold_out_subfloors" then
        util.raise.refresh(player, "production", nil)

    elseif preference_name == "ingredient_satisfaction" then
        if event.element.state == true then  -- only recalculate if enabled
            local realm = util.globals.player_table(player).realm
            for district in realm:iterator() do
                for factory in district:iterator() do
                    solver.determine_ingredient_satisfaction(factory)
                end
            end
        end
        util.raise.refresh(player, "production", nil)

    elseif preference_name == "attach_factory_products" or preference_name == "skip_factory_naming" then
        util.raise.refresh(player, "factory_list", nil)

    elseif preference_name == "show_gui_button" then
        util.gui.toggle_mod_gui(player)
    end
end

local function handle_dropdown_preference_change(player, tags, event)
    local selected_index = event.element.selected_index
    local preferences = util.globals.preferences(player)

    if tags.name == "products_per_row" then
        preferences.products_per_row = PRODUCTS_PER_ROW_OPTIONS[selected_index]
        util.globals.modal_data(player).rebuild = true
    elseif tags.name == "factory_list_rows" then
        preferences.factory_list_rows = FACTORY_LIST_ROWS_OPTIONS[selected_index]
        util.globals.modal_data(player).rebuild = true
    elseif tags.name == "default_timescale" then
        local index_map = {[1] = 1, [2] = 60, [3] = 3600}
        preferences.default_timescale = index_map[selected_index]
    end
end

local function handle_mb_default_change(player, tags, event)
    local mb_defaults = util.globals.preferences(player).mb_defaults
    local module_name = event.element.elem_value

    mb_defaults[tags.type] = (module_name ~= nil) and MODULE_NAME_MAP[module_name] or nil
end

local function handle_bol_change(player, _, event)
    local player_table = util.globals.player_table(player)
    local defined_by = (event.element.switch_state == "left") and "belts" or "lanes"

    player_table.preferences.belts_or_lanes = defined_by
    view_state.rebuild_state(player)

    -- Go through every factory's top level products and update their defined_by
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            solver.determine_ingredient_satisfaction(factory)
        end
    end

    solver.update(player, nil)
    util.raise.refresh(player, "all", nil)
end

local function handle_default_prototype_change(player, tags, event)
    local type = tags.type
    local category_id = tags.category_id

    local modal_elements = util.globals.modal_elements(player)
    prototyper.defaults.set(player, type, tags.prototype_id, category_id)
    refresh_defaults_table(player, modal_elements, type, category_id)

    -- If this was an shift-click, set this prototype on every category that also has it
    if event.shift and type == "machines" then
        local new_default_prototype = prototyper.defaults.get(player, type, category_id)

        for _, secondary_category in pairs(PROTOTYPE_MAPS[type]) do
            if table_size(secondary_category.members) > 1 then  -- don't attempt to change categories with only one machine
                local secondary_prototype = secondary_category.members[new_default_prototype.name]

                if secondary_prototype ~= nil then
                    prototyper.defaults.set(player, type, secondary_prototype.id, secondary_category.id)
                    refresh_defaults_table(player, modal_elements, type, secondary_category.id)
                end
            end
        end
    end

    if type == "belts" or type == "wagons" then
        view_state.rebuild_state(player)
        util.raise.refresh(player, "all", nil)
    end
end


local function open_preferences_dialog(player, modal_data)
    local preferences = util.globals.preferences(player)
    local modal_elements = modal_data.modal_elements

    local flow_content = modal_elements.dialog_flow.add{type="flow", direction="horizontal"}
    flow_content.style.horizontal_spacing = 12

    local function add_content_frame()
        local content_frame = flow_content.add{type="frame", direction="vertical", style="inside_shallow_frame"}
        content_frame.style.vertically_stretchable = true

        return content_frame.add{type="scroll-pane", style="flib_naked_scroll_pane"}
    end

    local left_content_frame = add_content_frame()
    left_content_frame.style.width = 300

    local general_preference_names = {"show_gui_button", "attach_factory_products", "skip_factory_naming",
    "prefer_matrix_solver", "show_floor_items", "fold_out_subfloors", "ingredient_satisfaction",
    "round_button_numbers", "ignore_barreling_recipes", "ignore_recycling_recipes"}
    local general_box = preference_structures.checkboxes(preferences, left_content_frame, "general",
    general_preference_names)

    general_box.add{type="line", direction="horizontal"}.style.margin = {4, 0, 2, 0}

    preference_structures.dropdowns(preferences, general_box)

    local production_preference_names = {"done_column", "percentage_column", "line_comment_column"}
    preference_structures.checkboxes(preferences, left_content_frame, "production", production_preference_names)

    left_content_frame.add{type="empty-widget", style="flib_vertical_pusher"}
    local support_frame = left_content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    support_frame.style.bottom_margin = -12
    support_frame.style.padding = 8
    support_frame.add{type="label", caption={"fp.preferences_support"}}

    local right_content_frame = add_content_frame()

    preference_structures.mb_defaults(preferences, right_content_frame)

    local belts_box = preference_structures.prototypes(player, right_content_frame, modal_elements, "belts")
    preference_structures.prototypes(player, right_content_frame, modal_elements, "beacons")
    preference_structures.prototypes(player, right_content_frame, modal_elements, "wagons")
    preference_structures.prototypes(player, right_content_frame, modal_elements, "fuels")
    preference_structures.prototypes(player, right_content_frame, modal_elements, "machines")

    belts_box.visible = true  -- force visible so additional preference is accessible
    belts_box.title_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    local switch_state = (preferences.belts_or_lanes == "belts") and "left" or "right"
    belts_box.title_flow.add{type="switch", switch_state=switch_state, tooltip={"fp.preference_belts_or_lanes_tt"},
        tags={mod="fp", on_gui_switch_state_changed="choose_belts_or_lanes"},
        left_label_caption={"fp.pu_belt", 2}, right_label_caption={"fp.pu_lane", 2}}
end

local function close_preferences_dialog(player, _)
    local ui_state = util.globals.ui_state(player)
    if ui_state.modal_data.rebuild then
        main_dialog.rebuild(player, true)
        ui_state.modal_data = {}  -- fix as rebuild deletes the table
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "select_preference_default",
            handler = handle_default_prototype_change
        }
    },
    on_gui_text_changed = {
        {
            name = "mb_default_beacon_amount",
            handler = (function(player, _, event)
                local mb_defaults = util.globals.preferences(player).mb_defaults
                mb_defaults.beacon_count = tonumber(event.element.text)
            end)
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "toggle_preference",
            handler = handle_checkbox_preference_change
        }
    },
    on_gui_selection_state_changed = {
        {
            name = "choose_preference",
            handler = handle_dropdown_preference_change
        }
    },
    on_gui_elem_changed = {
        {
            name = "change_mb_default",
            handler = handle_mb_default_change
        }
    },
    on_gui_switch_state_changed = {
        {
            name = "choose_belts_or_lanes",
            handler = handle_bol_change
        }
    },
}

listeners.dialog = {
    dialog = "preferences",
    metadata = (function(_) return {
        caption = {"fp.preferences"},
        create_content_frame = false,
        reset_handler_name = "reset_preferences"
    } end),
    open = open_preferences_dialog,
    close = close_preferences_dialog
}

listeners.global = {
    reset_preferences = (function(player)
        local player_table = util.globals.player_table(player)
        player_table.preferences = nil
        reload_preferences(player_table)
        -- Pretty heavy way to reset, but it's very simple
        player_table.ui_state.modal_data.rebuild = true
        util.raise.close_dialog(player, "cancel")
        util.raise.open_dialog(player, {dialog="preferences"})
    end)
}

return { listeners }

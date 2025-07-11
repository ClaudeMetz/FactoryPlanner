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
    local gui_id = (category_id) and (type .. "-" .. category_id) or type
    local table_prototypes = modal_elements[gui_id]
    table_prototypes.clear()

    local prototypes = storage.prototypes[type]
    if category_id then prototypes = prototypes[category_id].members end
    local default = defaults.get(player, type, category_id)

    for prototype_id, prototype in ipairs(prototypes) do
        local selected = (default.proto.id == prototype_id)
        local style = (selected) and "flib_slot_button_green_small" or "flib_slot_button_default_small"
        local elem_type = (default.quality) and prototype.elem_type .. "-with-quality" or prototype.elem_type
        local quality = (default.quality) and default.quality.name or nil
        local tooltip = {type=elem_type, name=prototype.name, quality=quality}

        table_prototypes.add{type="sprite-button", sprite=prototype.sprite, style=style, elem_tooltip=tooltip,
            tags={mod="fp", on_gui_click="select_preference_default", type=type, prototype_name=prototype.name,
            category_id=category_id}, quality=quality, mouse_button_filter={"left"}}
    end

    return #prototypes
end

local function refresh_views_table(player)
    local view_preferences = util.globals.preferences(player).item_views
    local views_table = util.globals.modal_elements(player).views_table
    local views = util.globals.ui_state(player).views_data.views

    local function add_move_button(parent, index, direction, enabled)
        local move_up_button = parent.add{type="sprite-button", sprite="fp_arrow_" .. direction,
            tags={mod="fp", on_gui_click="move_view", index=index, direction=direction},
            enabled=enabled, style="fp_sprite-button_move", mouse_button_filter={"left"}}
        move_up_button.style.size = {20, 18}
        move_up_button.style.padding = 0
    end

    local active_view_count = 0
    for _, view_preference in ipairs(view_preferences.views) do
        if view_preference.enabled then active_view_count = active_view_count + 1 end
    end

    views_table.clear()
    for index, view_preference in ipairs(view_preferences.views) do
        local view_data = views[view_preference.name]

        local enabled = (active_view_count < 4 or view_preference.enabled) and
            (active_view_count > 1 or not view_preference.enabled)
        views_table.add{type="checkbox", state=view_preference.enabled, enabled=enabled,
            tags={mod="fp", on_gui_checked_state_changed="toggle_view", name=view_preference.name}}

        local flow_name = views_table.add{type="flow", direction="horizontal"}
        flow_name.add{type="label", caption=view_data.caption, tooltip=view_data.tooltip}
        flow_name.style.horizontally_stretchable = true

        local flow_move = views_table.add{type="flow", direction="horizontal"}
        flow_move.style.horizontal_spacing = 0
        add_move_button(flow_move, index, "up", (index > 1))
        add_move_button(flow_move, index, "down", (index < #view_preferences.views))
    end
end


local function add_checkboxes_box(preferences, content_frame, type, preference_names)
    local preference_box = add_preference_box(content_frame, type)
    local flow_checkboxes = preference_box.add{type="flow", direction="vertical"}
    flow_checkboxes.style.right_padding = 16

    for _, pref_name in ipairs(preference_names) do
        local identifier = type .. "_" .. pref_name
        local caption = {"fp.info_label", {"fp.preference_" .. identifier}}
        local tooltip ={"fp.preference_" .. identifier .. "_tt"}
        flow_checkboxes.add{type="checkbox", state=preferences[pref_name], caption=caption, tooltip=tooltip,
            tags={mod="fp", on_gui_checked_state_changed="toggle_preference", type=type, name=pref_name}}
    end

    return preference_box
end

local function add_dropdowns(preferences, parent_flow)
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
        height_items[index] = {"", value .. " ", {"fp.pl_factory", 2}}
        if value == preferences.factory_list_rows then height_index = index end
    end
    add_dropdown("factory_list_rows", height_items, height_index)

    local compact_items, compact_index = {}, nil
    for index, value in pairs(COMPACT_WIDTH_PERCENTAGE) do
        compact_items[index] = {"", value .. " %"}
        if value == preferences.compact_width_percentage then compact_index = index end
    end
    add_dropdown("compact_width_percentage", compact_items, compact_index)
end


local function add_views_box(player, content_frame, modal_elements)
    local preference_box = add_preference_box(content_frame, "views")

    local label = preference_box.add{type="label", caption={"fp.preference_pick_views"}}
    label.style.bottom_margin = 4

    local frame_views = preference_box.add{type="frame", style="deep_frame_in_shallow_frame"}
    local table_views = frame_views.add{type="table", style="table_with_selection", column_count=3}
    modal_elements["views_table"] = table_views

    refresh_views_table(player)
end


local function add_default_proto_box(player, content_frame, type, category_id, addition)
    local modal_elements = util.globals.modal_elements(player)
    local preference_box = add_preference_box(content_frame, "default_" .. type)

    local frame = preference_box.add{type="frame", direction="horizontal", style="fp_frame_light_slots_small"}
    local gui_id = (category_id) and (type .. "-" .. category_id) or type
    modal_elements[gui_id] = frame.add{type="table", column_count=8, style="fp_table_slots_small"}
    local prototype_count = refresh_defaults_table(player, modal_elements, type, category_id)

    if addition == "lanes_or_belts" then
        preference_box.title_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
        local belts_or_lanes = util.globals.preferences(player).belts_or_lanes
        local switch_state = (belts_or_lanes == "belts") and "left" or "right"
        preference_box.title_flow.add{type="switch", switch_state=switch_state,
            tooltip={"fp.preference_belts_or_lanes_tt"},
            tags={mod="fp", on_gui_switch_state_changed="choose_belts_or_lanes"},
            left_label_caption={"fp.pu_belt", 2}, right_label_caption={"fp.pu_lane", 2}}

    elseif addition == "quality_picker" and MULTIPLE_QUALITIES then
        preference_box.title_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
        local default_quality = defaults.get(player, type, category_id).quality
        local tags = {mod="fp", on_gui_selection_state_changed="select_preference_quality",
            type=type, category_id=category_id}
        util.gui.add_quality_dropdown(preference_box.title_flow, default_quality.id, tags)
    end

    -- This is inefficient, but it's fine
    if not MULTIPLE_QUALITIES and prototype_count == 1 then preference_box.destroy() end
end


local function handle_checkbox_preference_change(player, tags, event)
    local preference_name = tags.name
    util.globals.preferences(player)[preference_name] = event.element.state

    if tags.type == "production" or preference_name == "show_floor_items" then
        util.raise.refresh(player, "production")

    elseif preference_name == "ingredient_satisfaction" then
        if event.element.state == true then  -- only recalculate if enabled
            local realm = util.globals.player_table(player).realm
            for district in realm:iterator() do
                for factory in district:iterator() do
                    solver.determine_ingredient_satisfaction(factory)
                end
            end
        end
        util.raise.refresh(player, "production")

    elseif preference_name == "attach_factory_products" or preference_name == "skip_factory_naming" then
        util.raise.refresh(player, "factory_list")

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
    elseif tags.name == "compact_width_percentage" then
        preferences.compact_width_percentage = COMPACT_WIDTH_PERCENTAGE[selected_index]
        util.globals.modal_data(player).rebuild_compact = true
    end
end

local function handle_view_toggle(player, tags, _)
    local view_preferences = util.globals.preferences(player).item_views
    for index, view_preference in ipairs(view_preferences.views) do
        if view_preference.name == tags.name then
            view_preference.enabled = not view_preference.enabled
            -- Select a valid view if the current one is disabled
            if not view_preference.enabled and view_preferences.selected_index == index then
                item_views.cycle_views(player, "standard")
            end
            break
        end
    end

    item_views.refresh_interface(player)
    refresh_views_table(player)

    util.raise.refresh(player, "factory")
end

local function handle_view_move(player, tags, _)
    local view_preferences = util.globals.preferences(player).item_views
    local view_preference = table.remove(view_preferences.views, tags.index)
    local new_index = (tags.direction == "up") and (tags.index-1) or (tags.index+1)
    table.insert(view_preferences.views, new_index, view_preference)

    item_views.rebuild_interface(player)  -- rebuild because of the move
    refresh_views_table(player)

    util.raise.refresh(player, "factory")
end

local function handle_bol_change(player, _, event)
    local player_table = util.globals.player_table(player)
    local defined_by = (event.element.switch_state == "left") and "belts" or "lanes"

    player_table.preferences.belts_or_lanes = defined_by

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)
    refresh_views_table(player)

    solver.update(player, nil)
    util.raise.refresh(player, "all")
end

local function handle_default_prototype_change(player, tags, _)
    local data_type, category_id = tags.type, tags.category_id

    local current_default = defaults.get(player, data_type, category_id)
    local quality_name = (current_default.quality) and current_default.quality.name or nil
    local default_data = {prototype=tags.prototype_name,  quality=quality_name}
    defaults.set(player, data_type, default_data, category_id)

    local modal_elements = util.globals.modal_elements(player)
    refresh_defaults_table(player, modal_elements, data_type, category_id)

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)
    refresh_views_table(player)

    util.raise.refresh(player, "all")
end

local function handle_prototype_quality_change(player, tags, event)
    local data_type, category_id = tags.type, tags.category_id
    -- Get the quality_proto by using the index as the quality level
    local quality_proto = storage.prototypes.qualities[event.element.selected_index]

    local current_default = defaults.get(player, data_type, category_id)
    local default_data = {prototype=current_default.proto.name, quality=quality_proto.name}
    defaults.set(player, data_type, default_data, category_id)

    local modal_elements = util.globals.modal_elements(player)
    refresh_defaults_table(player, modal_elements, data_type, category_id)

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)

    util.raise.refresh(player, "all")
end


local function open_preferences_dialog(player, modal_data)
    local preferences = util.globals.preferences(player)
    local modal_elements = modal_data.modal_elements

    -- Left side
    local left_content_frame = modal_elements.content_frame

    local general_preference_names = {"show_gui_button", "skip_factory_naming", "attach_factory_products",
        "prefer_matrix_solver", "show_floor_items", "ingredient_satisfaction", "ignore_barreling_recipes",
        "ignore_recycling_recipes"}
    local general_box = add_checkboxes_box(preferences, left_content_frame, "general", general_preference_names)

    general_box.add{type="line", direction="horizontal"}.style.margin = {4, 0, 2, 0}
    add_dropdowns(preferences, general_box)

    local production_preference_names = {"done_column", "percentage_column", "line_comment_column"}
    add_checkboxes_box(preferences, left_content_frame, "production", production_preference_names)

    left_content_frame.add{type="empty-widget", style="flib_vertical_pusher"}
    local support_frame = left_content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    support_frame.style.top_padding = 8
    support_frame.add{type="label", caption={"fp.preferences_support"}}

    -- Right side
    local right_content_frame = modal_elements.secondary_frame
    add_views_box(player, right_content_frame, modal_elements)
    right_content_frame.add{type="empty-widget", style="flib_vertical_pusher"}
    add_default_proto_box(player, right_content_frame, "belts", nil, "lanes_or_belts")
    add_default_proto_box(player, right_content_frame, "pumps", nil, "quality_picker")
    add_default_proto_box(player, right_content_frame, "wagons", 1, "quality_picker")  -- cargo-wagon
    add_default_proto_box(player, right_content_frame, "wagons", 2, "quality_picker")  -- fluid-wagon
end

local function close_preferences_dialog(player, _)
    local ui_state = util.globals.ui_state(player)
    if ui_state.modal_data.rebuild then
        main_dialog.rebuild(player, true)
        ui_state.modal_data = {}  -- fix as rebuild deletes the table
    elseif ui_state.modal_data.rebuild_compact then
        compact_dialog.rebuild(player, false)
    end
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "select_preference_default",
            handler = handle_default_prototype_change
        },
        {
            name = "move_view",
            handler = handle_view_move
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "toggle_preference",
            handler = handle_checkbox_preference_change
        },
        {
            name = "toggle_view",
            handler = handle_view_toggle
        }
    },
    on_gui_selection_state_changed = {
        {
            name = "choose_preference",
            handler = handle_dropdown_preference_change
        },
        {
            name = "select_preference_quality",
            handler = handle_prototype_quality_change
        },
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
        secondary_frame = true,
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

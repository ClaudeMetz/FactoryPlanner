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
    local default_proto = prototyper.defaults.get(player, type, category_id).proto

    for prototype_id, prototype in ipairs(prototypes) do
        local selected = (default_proto.id == prototype_id)
        local style = (selected) and "flib_slot_button_green_small" or "flib_slot_button_default_small"
        local tooltip = {type=prototype.elem_type, name=prototype.name}

        table_prototypes.add{type="sprite-button", sprite=prototype.sprite, style=style, elem_tooltip=tooltip,
            tags={mod="fp", on_gui_click="select_preference_default", type=type, prototype_name=prototype.name,
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
end

function preference_structures.belts(player, content_frame, modal_elements)
    local preference_box = add_preference_box(content_frame, "default_belts")
    local table_prototypes = preference_box.add{type="table", column_count=3}
    table_prototypes.style.horizontal_spacing = 20
    table_prototypes.style.vertical_spacing = 8
    table_prototypes.style.top_margin = 4

    local frame = table_prototypes.add{type="frame", direction="horizontal", style="fp_frame_light_slots_small"}
    local table = frame.add{type="table", column_count=10, style="fp_table_slots_small"}
    modal_elements["belts"] = table
    refresh_defaults_table(player, modal_elements, "belts", nil)

    preference_box.title_flow.add{type="empty-widget", style="flib_horizontal_pusher"}
    local belts_or_lanes = util.globals.preferences(player).belts_or_lanes
    local switch_state = (belts_or_lanes == "belts") and "left" or "right"
    preference_box.title_flow.add{type="switch", switch_state=switch_state, tooltip={"fp.preference_belts_or_lanes_tt"},
        tags={mod="fp", on_gui_switch_state_changed="choose_belts_or_lanes"},
        left_label_caption={"fp.pu_belt", 2}, right_label_caption={"fp.pu_lane", 2}}
end

function preference_structures.wagons(player, content_frame, modal_elements)
    local preference_box = add_preference_box(content_frame, "default_wagons")
    local table_prototypes = preference_box.add{type="table", column_count=3}
    table_prototypes.style.horizontal_spacing = 20
    table_prototypes.style.vertical_spacing = 8
    table_prototypes.style.top_margin = 4

    local categories = global.prototypes.wagons
    if not next(categories) then preference_box.visible = false; return end

    local any_category_visible = false
    for category_id, category in ipairs(categories) do
        if #category.members > 1 then
            any_category_visible = true

            local category_caption = {"?", {"wagon-category-name." .. category.name}, "'" .. category.name .. "'"}
            table_prototypes.add{type="label", caption=category_caption}
            table_prototypes.add{type="empty-widget", style="flib_horizontal_pusher"}

            local frame = table_prototypes.add{type="frame", direction="horizontal", style="fp_frame_light_slots_small"}
            local table = frame.add{type="table", column_count=6, style="fp_table_slots_small"}
            modal_elements.wagons = modal_elements.wagons or {}
            modal_elements.wagons[category_id] = table

            refresh_defaults_table(player, modal_elements, "wagons", category_id)
        end
    end
    if not any_category_visible then preference_box.visible = false end
end


local function handle_checkbox_preference_change(player, tags, event)
    local preference_name = tags.name
    util.globals.preferences(player)[preference_name] = event.element.state

    if tags.type == "production" or preference_name == "round_button_numbers"
            or preference_name == "show_floor_items" or preference_name == "fold_out_subfloors" then
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
    end
end

local function handle_bol_change(player, _, event)
    local player_table = util.globals.player_table(player)
    local defined_by = (event.element.switch_state == "left") and "belts" or "lanes"

    player_table.preferences.belts_or_lanes = defined_by
    view_state.rebuild_state(player)

    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            solver.determine_ingredient_satisfaction(factory)
        end
    end

    solver.update(player, nil)
    util.raise.refresh(player, "all")
end

local function handle_default_prototype_change(player, tags, _)
    local data_type = tags.type
    local category_id = tags.category_id

    local modal_elements = util.globals.modal_elements(player)
    prototyper.defaults.set(player, data_type, {prototype=tags.prototype_name}, category_id)
    refresh_defaults_table(player, modal_elements, data_type, category_id)

    if data_type == "belts" or data_type == "wagons" then
        view_state.rebuild_state(player)
        util.raise.refresh(player, "all")
    end
end


local function open_preferences_dialog(player, modal_data)
    local preferences = util.globals.preferences(player)
    local modal_elements = modal_data.modal_elements

    -- Left side
    local left_content_frame = modal_elements.content_frame
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
    support_frame.style.top_margin = -4
    support_frame.add{type="label", caption={"fp.preferences_support"}}

    -- Right side
    local right_content_frame = modal_elements.secondary_frame

    preference_structures.belts(player, right_content_frame, modal_elements)
    preference_structures.wagons(player, right_content_frame, modal_elements)
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

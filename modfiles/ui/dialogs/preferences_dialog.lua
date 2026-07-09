---@class PreferencesDialogModalData: ModalData
---@field rebuild boolean?
---@field rebuild_compact boolean?

-- ** LOCAL UTIL **
---@param content_frame LuaGuiElement
---@param box_type string
---@return LuaGuiElement
local function add_preference_box(content_frame, box_type)
    local bordered_frame = content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    local title_flow = bordered_frame.add{type="flow", direction="horizontal", name="title_flow"}
    title_flow.style.vertical_align = "center"

    local caption = {"fp.info_label", {"fp.preference_".. box_type .. "_title"}}
    local tooltip = {"fp.preference_".. box_type .. "_title_tt"}
    title_flow.add{type="label", caption=caption, tooltip=tooltip, style="caption_label"}

    return bordered_frame
end

---@param player LuaPlayer
---@param modal_elements table
---@param data_type "belts"
---@param category_id integer?
---@return integer prototype_count
local function refresh_defaults_table(player, modal_elements, data_type, category_id)
    local gui_id = (category_id) and (data_type .. "-" .. category_id) or data_type
    local table_prototypes = modal_elements[gui_id]
    table_prototypes.clear()

    local prototypes = storage.prototypes[data_type]
    if category_id then prototypes = (prototypes[category_id]--[[@as IndexedCategory<FPPrototype>]]).members end
    local default = defaults.get(player, data_type, category_id)

    for prototype_id, prototype in ipairs(prototypes) do
        local selected = (default.proto.id == prototype_id)
        local style = (selected) and "fflib_slot_button_green_small" or "fflib_slot_button_default_small"
        local elem_type = (default.quality) and prototype.elem_type .. "-with-quality" or prototype.elem_type
        local quality = (default.quality) and default.quality.name or nil
        local tooltip = {type=elem_type, name=prototype.name, quality=quality}

        ---@class SelectPreferenceTableDefault
        ---@field data_type "belts"
        ---@field prototype_name string
        ---@field category_id integer?
        local tags = {mod="fp", on_gui_click="select_preference_table_default", data_type=data_type,
            prototype_name=prototype.name, category_id=category_id}
        table_prototypes.add{type="sprite-button", tags=tags, sprite=prototype.sprite, style=style,
            elem_tooltip=tooltip, quality=quality, mouse_button_filter={"left"}}
    end

    return #prototypes
end

---@param player LuaPlayer
local function refresh_views_table(player)
    local view_preferences = lib.globals.preferences(player).item_views
    local views_table = lib.globals.modal_elements(player).views_table  ---@as LuaGuiElement
    local view_data = lib.globals.ui_state(player).views_data

    ---@param parent LuaGuiElement
    ---@param index integer
    ---@param direction "up" | "down"
    ---@param enabled boolean
    local function add_move_button(parent, index, direction, enabled)
        ---@class MovePreferencesViewTags
        ---@field index integer
        ---@field direction "up" | "down"
        local tags = {mod="fp", on_gui_click="move_preferences_view", index=index, direction=direction}
        parent.add{type="sprite-button", tags=tags, sprite="fp_arrow_" .. direction,
            enabled=enabled, style="fp_sprite-button_move_small", mouse_button_filter={"left"}}
    end

    local active_view_count = 0
    for _, view_preference in ipairs(view_preferences.views) do
        if view_preference.enabled then active_view_count = active_view_count + 1 end
    end

    views_table.clear()
    for index, view_preference in ipairs(view_preferences.views) do
        local item_view_data = view_data--[[@cast -nil]].views[view_preference.name]

        ---@class TogglePreferencesViewTags
        ---@field name string
        local tags = {mod="fp", on_gui_checked_state_changed="toggle_preference_view", name=view_preference.name}
        local enabled = (active_view_count < 4 or view_preference.enabled) and
            (active_view_count > 1 or not view_preference.enabled)
        views_table.add{type="checkbox", tags=tags, state=view_preference.enabled, enabled=enabled}

        local flow_name = views_table.add{type="flow", direction="horizontal"}
        flow_name.add{type="label", caption=item_view_data.caption, tooltip=item_view_data.tooltip}
        flow_name.style.horizontally_stretchable = true

        local flow_move = views_table.add{type="flow", direction="horizontal"}
        flow_move.style.horizontal_spacing = 0
        add_move_button(flow_move, index, "up", (index > 1))
        add_move_button(flow_move, index, "down", (index < #view_preferences.views))
    end
end

---@alias CheckboxPreferenceDataType "general" | "production"

---@param preferences PreferencesTable
---@param content_frame LuaGuiElement
---@param data_type CheckboxPreferenceDataType
---@param preference_names string[]
---@return LuaGuiElement
local function add_checkboxes_box(preferences, content_frame, data_type, preference_names)
    local preference_box = add_preference_box(content_frame, data_type)
    local flow_checkboxes = preference_box.add{type="flow", direction="vertical"}
    flow_checkboxes.style.right_padding = 16

    for _, pref_name in ipairs(preference_names) do
        local identifier = data_type .. "_" .. pref_name
        local caption = {"fp.info_label", {"fp.preference_" .. identifier}}
        local tooltip ={"fp.preference_" .. identifier .. "_tt"}

        ---@class TogglePreferenceTags
        ---@field data_type CheckboxPreferenceDataType
        ---@field name string
        local tags = {mod="fp", on_gui_checked_state_changed="toggle_preference", data_type=data_type, name=pref_name}
        flow_checkboxes.add{type="checkbox", tags=tags, state=preferences[pref_name], caption=caption, tooltip=tooltip}
    end

    return preference_box
end

---@param preferences PreferencesTable
---@param parent_flow LuaGuiElement
local function add_dropdowns(preferences, parent_flow)
    ---@param name string
    ---@param items LocalisedString[]
    ---@param selected_index integer
    local function add_dropdown(name, items, selected_index)
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.top_margin = 4

        flow.add{type="label", caption={"fp.info_label", {"fp.preference_dropdown_" .. name}},
            tooltip={"fp.preference_dropdown_" .. name .. "_tt"}}
        flow.add{type="empty-widget", style="fflib_horizontal_pusher"}

        ---@class ChoosePreferenceTags
        ---@field name string
        local tags = {mod="fp", on_gui_selection_state_changed="choose_preference", name=name}
        flow.add{type="drop-down", tags=tags, items=items, selected_index=selected_index,
            style="fp_drop-down_slim"}
    end

    local width_items, width_index = {}, nil  ---@type LocalisedString[], integer?
    for index, value in pairs(lib.preferences.products_per_row_options) do
        width_items[index] = {"", value .. " ", {"fp.pl_product", 2}}
        if value == preferences.products_per_row then width_index = index end
    end
    add_dropdown("products_per_row", width_items, width_index--[[@cast -nil]])

    local height_items, height_index = {}, nil  ---@type LocalisedString[], integer?
    for index, value in pairs(lib.preferences.factory_list_rows_options) do
        height_items[index] = {"", value .. " ", {"fp.pl_factory", 2}}
        if value == preferences.factory_list_rows then height_index = index end
    end
    add_dropdown("factory_list_rows", height_items, height_index--[[@cast -nil]])

    local compact_items, compact_index = {}, nil  ---@type LocalisedString[], integer?
    for index, value in pairs(lib.preferences.compact_width_percentages) do
        compact_items[index] = {"", value .. " %"}
        if value == preferences.compact_width_percentage then compact_index = index end
    end
    add_dropdown("compact_width_percentage", compact_items, compact_index--[[@cast -nil]])
end


---@param player LuaPlayer
---@param content_frame LuaGuiElement
---@param modal_elements table
local function add_views_box(player, content_frame, modal_elements)
    local preference_box = add_preference_box(content_frame, "views")

    local label = preference_box.add{type="label", caption={"fp.preference_pick_views"}}
    label.style.bottom_margin = 4

    local frame_views = preference_box.add{type="frame", style="deep_frame_in_shallow_frame"}
    local table_views = frame_views.add{type="table", style="table_with_selection", column_count=3}
    modal_elements["views_table"] = table_views

    refresh_views_table(player)
end


---@param player LuaPlayer
---@param content_frame LuaGuiElement
local function add_belts_proto_box(player, content_frame)
    local modal_elements = lib.globals.modal_elements(player)
    local preference_box = add_preference_box(content_frame, "default_belts")

    local frame = preference_box.add{type="frame", direction="horizontal", style="fp_frame_light_slots_small"}
    modal_elements["belts"] = frame.add{type="table", column_count=8, style="fp_table_slots_small"}
    refresh_defaults_table(player, modal_elements, "belts", nil)

    preference_box.title_flow.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local belts_or_lanes = lib.globals.preferences(player).belts_or_lanes
    local switch_state = (belts_or_lanes == "belts") and "left" or "right"
    preference_box.title_flow.add{type="switch", switch_state=switch_state,
        tooltip={"fp.preference_belts_or_lanes_tt"},
        tags={mod="fp", on_gui_switch_state_changed="choose_belts_or_lanes"},
        left_label_caption={"fp.pu_belt", 2}, right_label_caption={"fp.pu_lane", 2}}
end

---@alias ProtoPreferenceDataType "pumps" | "silos" | "wagons"

---@param player LuaPlayer
---@param content_frame LuaGuiElement
---@param data_type ProtoPreferenceDataType
---@param category_id integer?
---@param filter_type "pump" | "rocket-silo" | "cargo-wagon" | "fluid-wagon"
local function add_default_proto_box(player, content_frame, data_type, category_id, filter_type)
    local flow = content_frame.add{type="flow", direction="horizontal"}
    flow.style.vertical_align = "center"
    flow.add{type="label", caption={"fp.pu_" .. data_type:sub(1, -2), 1}}
    flow.add{type="empty-widget", style="fflib_horizontal_pusher"}

    ---@class SelectPreferenceBoxDefaultTags
    ---@field data_type ProtoPreferenceDataType
    ---@field category_id integer?
    local tags = {mod="fp", on_gui_elem_changed="select_preference_box_default", data_type=data_type,
        category_id=category_id}
    local filter = {{filter="type", type=filter_type}, {filter="hidden", invert=true, mode="and"}}
    local button_module = flow.add{type="choose-elem-button", tags=tags--[[@as Tags]], elem_type="entity-with-quality",
        elem_filters=filter, style="fp_sprite-button_inset", mouse_button_filter={"left"}}
    button_module.elem_value = defaults.get_as_elem_value(player, data_type, category_id)
end

---@param modal_elements table
local function add_export_box(modal_elements)
    modal_elements.titlebar_flow.visible = true
    local export_toggle_button = modal_elements.titlebar_flow.add{type="sprite-button", sprite="fp_export",
        tooltip={"fp.preferences_export_tt"}, tags={mod="fp", on_gui_click="preferences_toggle_export"},
        style="fp_button_frame", auto_toggle=true, mouse_button_filter={"left"}}
    modal_elements.export_toggle_button = export_toggle_button

    local export_content_frame = modal_elements.auxiliary_flow.add{type="frame",
        direction="vertical", style="inside_shallow_frame"}
    export_content_frame.style.top_margin = 8
    export_content_frame.style.padding = 12
    export_content_frame.visible = false
    modal_elements.export_content_frame = export_content_frame

    local export_flow = export_content_frame.add{type="flow", direction="horizontal"}
    export_flow.style.horizontal_spacing = 16
    export_flow.style.vertical_align = "center"

    export_flow.add{type="label", caption={"fp.preferences_export_string"}, tooltip={"fp.preferences_export_string_tt"}}
    local export_textfield = export_flow.add{type="textfield"}
    export_textfield.style.width = 0  -- needs to be set to 0 so stretching works
    export_textfield.style.horizontally_stretchable = true
    modal_elements.export_textfield = export_textfield

    export_flow.add{type="button", caption={"fp.export"}, style="fp_button_green", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="preferences_export"}}
    export_flow.add{type="button", caption={"fp.import"}, style="fp_button_green", mouse_button_filter={"left"},
        tags={mod="fp", on_gui_click="preferences_import"}}

    local export_label = modal_elements.export_content_frame.add{type="label", caption=""}
    export_label.style.top_margin = 8
    export_label.style.single_line = false
    export_label.visible = false
    modal_elements.export_label = export_label
end

---@param player LuaPlayer
---@param tags TogglePreferenceTags
---@param event EventData.on_gui_checked_state_changed
local function handle_checkbox_preference_change(player, tags, event)
    local preference_name = tags.name
    lib.globals.preferences(player)[preference_name] = event.element.state

    if tags.data_type == "production" or preference_name == "show_floor_items" then
        lib.gui.run_refresh(player, "production")

    elseif preference_name == "ingredient_satisfaction" then
        if event.element.state == true then  -- only recalculate if enabled
            local realm = lib.globals.player_table(player).realm
            realm:schedule_solver_updates(game.tick, player)

            solver.update(player)  -- update current factory right away
        end
        lib.gui.run_refresh(player, "production")

    elseif preference_name == "calculate_emissions" then
        local realm = lib.globals.player_table(player).realm
        realm:schedule_solver_updates(game.tick, player)

        solver.update(player)  -- update current factory right away
        lib.gui.run_refresh(player, "production")

    elseif preference_name == "attach_factory_products" or preference_name == "skip_factory_naming" then
        lib.gui.run_refresh(player, "factory_list")

    elseif preference_name == "show_gui_button" then
        lib.gui.toggle_mod_gui(player)
    end
end

---@param player LuaPlayer
---@param tags ChoosePreferenceTags
---@param event EventData.on_gui_selection_state_changed
local function handle_dropdown_preference_change(player, tags, event)
    local selected_index = event.element.selected_index  ---@as integer
    local preferences = lib.globals.preferences(player)
    local modal_data = lib.globals.modal_data(player)  ---@as PreferencesDialogModalData

    if tags.name == "products_per_row" then
        preferences.products_per_row = lib.preferences.products_per_row_options[selected_index]
        modal_data.rebuild = true
    elseif tags.name == "factory_list_rows" then
        preferences.factory_list_rows = lib.preferences.factory_list_rows_options[selected_index]
        modal_data.rebuild = true
    elseif tags.name == "compact_width_percentage" then
        preferences.compact_width_percentage = lib.preferences.compact_width_percentages[selected_index]
        modal_data.rebuild_compact = true
    end
end

---@param player LuaPlayer
---@param tags TogglePreferencesViewTags
local function handle_view_toggle(player, tags, _)
    local view_preferences = lib.globals.preferences(player).item_views
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

    lib.gui.run_refresh(player, "factory")
end

---@param player LuaPlayer
---@param tags MovePreferencesViewTags
local function handle_view_move(player, tags, _)
    local view_preferences = lib.globals.preferences(player).item_views
    local view_preference = table.remove(view_preferences.views, tags.index)
    local new_index = (tags.direction == "up") and (tags.index-1) or (tags.index+1)
    table.insert(view_preferences.views, new_index, view_preference)

    -- Make sure the selected view stays selected
    local selected = view_preferences.selected_index
    if tags.index == selected then
        view_preferences.selected_index = new_index
    elseif tags.index < selected and new_index >= selected then
        view_preferences.selected_index = selected - 1
    elseif tags.index > selected and new_index <= selected then
        view_preferences.selected_index = selected + 1
    end

    item_views.rebuild_interface(player)  -- rebuild because of the move
    refresh_views_table(player)

    lib.gui.run_refresh(player, "factory")
end

---@param player LuaPlayer
---@param event EventData.on_gui_switch_state_changed
local function handle_bol_change(player, _, event)
    local player_table = lib.globals.player_table(player)
    local defined_by = (event.element.switch_state == "left") and "belts" or "lanes"

    player_table.preferences.belts_or_lanes = defined_by

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)
    refresh_views_table(player)

    solver.update(player)
    lib.gui.run_refresh(player, "factory")
end

---@param player LuaPlayer
---@param tags SelectPreferenceTableDefault
local function handle_table_default_change(player, tags, _)
    local data_type, category_id = tags.data_type, tags.category_id

    local current_default = defaults.get(player, data_type, category_id)
    local quality_name = (current_default.quality) and current_default.quality.name or nil
    local default_data = {prototype=tags.prototype_name,  quality=quality_name}
    defaults.set(player, data_type, default_data, category_id)

    local modal_elements = lib.globals.modal_elements(player)
    refresh_defaults_table(player, modal_elements, data_type, category_id)

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)
    refresh_views_table(player)

    lib.gui.run_refresh(player, "factory")
end

---@param player LuaPlayer
---@param tags SelectPreferenceBoxDefaultTags
---@param event EventData.on_gui_elem_changed
local function handle_box_default_change(player, tags, event)
    local data_type, category_id = tags.data_type, tags.category_id

    local elem_value = event.element.elem_value  ---@as PrototypeWithQuality
    if not elem_value then
        event.element.elem_value = defaults.get_as_elem_value(player, data_type, category_id)
        lib.cursor.create_flying_text(player, {"fp.no_removal", {"fp.pu_" .. data_type:sub(1, -2), 1}})
        return  -- nothing changed
    end

    local machine_proto = prototyper.util.find(data_type, elem_value.name, category_id)  ---@as FPMachinePrototype
    local quality_proto = prototyper.util.find("qualities", elem_value.quality, nil)  ---@as FPQualityPrototype
    local default_data = {prototype=machine_proto.name, quality=quality_proto.name}
    defaults.set(player, data_type, default_data, category_id)

    item_views.rebuild_data(player)
    item_views.rebuild_interface(player)

    lib.gui.run_refresh(player, "factory")
end

---@param player LuaPlayer
---@param modal_data PreferencesDialogModalData
local function open_preferences_dialog(player, modal_data)
    local preferences = lib.globals.preferences(player)
    local modal_elements = modal_data.modal_elements

    -- Left side
    local left_content_frame = modal_elements.content_frame

    local general_preference_names = {"show_gui_button", "skip_factory_naming", "attach_factory_products",
        "prefer_matrix_solver", "show_floor_items", "ingredient_satisfaction", "calculate_emissions",
        "ignore_barreling_recipes", "ignore_recycling_recipes"}
    local general_box = add_checkboxes_box(preferences, left_content_frame, "general", general_preference_names)

    general_box.add{type="line", direction="horizontal"}.style.margin = {4, 0, 2, 0}
    add_dropdowns(preferences, general_box)

    local production_preference_names = {"done_column", "percentage_column", "line_comment_column"}
    add_checkboxes_box(preferences, left_content_frame, "production", production_preference_names)

    left_content_frame.add{type="empty-widget", style="fflib_vertical_pusher"}
    local support_frame = left_content_frame.add{type="frame", direction="vertical", style="fp_frame_bordered_stretch"}
    support_frame.style.top_padding = 8
    support_frame.add{type="label", caption={"fp.preferences_support"}}

    -- Right side
    local right_content_frame = modal_elements.secondary_frame
    add_views_box(player, right_content_frame, modal_elements)
    add_belts_proto_box(player, right_content_frame)

    local preference_box = add_preference_box(right_content_frame, "box_defaults")
    local default_boxes_table = preference_box.add{type="table", column_count=2}
    default_boxes_table.style.horizontal_spacing = 60
    default_boxes_table.style.vertical_spacing = 8
    default_boxes_table.style.right_margin = 50
    add_default_proto_box(player, default_boxes_table, "pumps", nil, "pump")
    add_default_proto_box(player, default_boxes_table, "silos", nil, "rocket-silo")
    add_default_proto_box(player, default_boxes_table, "wagons", 1, "cargo-wagon")
    add_default_proto_box(player, default_boxes_table, "wagons", 2, "fluid-wagon")

    local pusher = right_content_frame.add{type="empty-widget", style="fflib_vertical_pusher"}
    pusher.style.top_margin = -4  -- counteract vertical spacing

    add_export_box(modal_elements)  -- export UI
end

---@param player LuaPlayer
local function close_preferences_dialog(player, _)
    local ui_state = lib.globals.ui_state(player)
    ---@cast ui_state.modal_data PreferencesDialogModalData
    if ui_state.modal_data.rebuild then
        main_dialog.rebuild(player, true)
        ---@diagnostic disable-next-line
        ui_state.modal_data = {}  -- fix as rebuild deletes the table
    elseif ui_state.modal_data.rebuild_compact then
        compact_dialog.rebuild(player, false)
    end
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "select_preference_table_default",
            handler = handle_table_default_change
        },
        {
            name = "move_preferences_view",
            handler = handle_view_move
        },
        {
            name = "preferences_toggle_export",
            handler = function(player, _, _)
                local modal_elements = lib.globals.modal_elements(player)
                local state = modal_elements.export_toggle_button.toggled
                modal_elements.export_content_frame.visible = state
                modal_elements.export_label.visible = false
            end
        },
        {
            name = "preferences_export",
            handler = function(player, _, _)
                local modal_elements = lib.globals.modal_elements(player)
                modal_elements.export_textfield.text = lib.preferences.export(player)
                lib.gui.select_all(modal_elements.export_textfield)
                modal_elements.export_label.visible = false
            end
        },
        {
            name = "preferences_import",
            handler = function(player, _, _)
                local modal_elements = lib.globals.modal_elements(player)
                local error = lib.preferences.import(player, modal_elements.export_textfield.text)
                modal_elements.export_label.visible = (error ~= nil)

                if error ~= nil then  -- something went wrong
                    modal_elements.export_label.caption = {"fp.error_message", {"fp.preferences_" .. error}}
                else
                    -- This rebuilds the main interface implicitly
                    GLOBAL_HANDLERS["shrinkwrap_interface"]{player_index=player.index}
                    lib.gui.open_dialog(player, {dialog="preferences"})
                end
            end
        }
    },
    on_gui_elem_changed = {
        {
            name = "select_preference_box_default",
            handler = handle_box_default_change
        }
    },
    on_gui_checked_state_changed = {
        {
            name = "toggle_preference",
            handler = handle_checkbox_preference_change
        },
        {
            name = "toggle_preference_view",
            handler = handle_view_toggle
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
}  ---@as GUIListenerDefinition

listeners.dialog = {
    dialog = "preferences",
    metadata = function(_)
        return {
            caption = {"fp.preferences"},
            secondary_frame = true,
            reset_handler_name = "reset_preferences"
        }  ---@as ModalDialogSettings
    end,
    open = open_preferences_dialog,
    close = close_preferences_dialog
}

listeners.global = {
    reset_preferences = function(player)
        local player_table = lib.globals.player_table(player)
        player_table.preferences = nil
        lib.preferences.reload(player_table)

        -- This rebuilds the main interface implicitly
        GLOBAL_HANDLERS["shrinkwrap_interface"]{player_index=player.index}
        lib.gui.open_dialog(player, {dialog="preferences"})
    end
}

return { listeners }

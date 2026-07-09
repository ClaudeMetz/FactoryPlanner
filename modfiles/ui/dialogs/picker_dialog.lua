local TLProduct = require("backend.data.TLProduct")

---@alias ItemCategory "product" | "byproduct" | "ingredient"

---@class PickerDialogModalData: ModalData
---@field item_id ObjectID?
---@field item_category ItemCategory
---@field create_factory boolean?
---@field item TLProduct?
---@field timescale Timescale
---@field belts_or_lanes BeltsOrLanes
---@field amount_defined_by ProductDefinedBy
---@field item_proto FPItemPrototype?
---@field belt_proto FPBeltPrototype?
---@field selected_group_id integer?

-- This dialog works as the product picker currently, but could also work as an ingredient picker down the line
-- ** ITEM PICKER **
---@param modal_data PickerDialogModalData
---@param new_group_id integer
local function select_item_group(modal_data, new_group_id)
    modal_data.selected_group_id = new_group_id

    for group_id, group_elements in pairs(modal_data.modal_elements.groups) do
        local selected_group = (group_id == new_group_id)
        group_elements.button.toggled = selected_group
        group_elements.scroll_pane.visible = selected_group
    end
end

---@param player LuaPlayer
---@param search_term string
local function search_picker_items(player, search_term)
    local modal_data = lib.globals.modal_data(player)  ---@as PickerDialogModalData
    local modal_elements = modal_data.modal_elements

    -- Groups are indexed continuously, so using ipairs here is fine
    local first_visible_group_id = nil
    for group_id, group in ipairs(modal_elements.groups) do
        local any_item_visible = false

        for _, subgroup_table in pairs(group.subgroup_tables) do
            for item_data, element in pairs(subgroup_table) do
                -- Can only get to this if translations are complete, as the textfield is disabled otherwise
                local visible = (search_term == item_data.name)
                    or (string.find(item_data.translated_name, search_term, 1, true) ~= nil)
                element.visible = visible
                any_item_visible = any_item_visible or visible
            end
        end

        group.button.visible = any_item_visible
        first_visible_group_id = first_visible_group_id or ((any_item_visible) and group_id or nil)
    end

    local any_result_found = (first_visible_group_id ~= nil)
    modal_elements.warning_label.visible = not any_result_found
    modal_elements.filter_frame.visible = any_result_found

    if first_visible_group_id ~= nil then
        local selected_group_id = modal_data.selected_group_id
        local is_selected_group_visible = modal_elements.groups[selected_group_id].button.visible
        local group_id_to_select = is_selected_group_visible and selected_group_id or first_visible_group_id
        select_item_group(modal_data, group_id_to_select)
    end
end

---@param parent_flow LuaGuiElement
---@param player LuaPlayer
local function add_item_picker(parent_flow, player)
    local player_table = lib.globals.player_table(player)
    local modal_data = player_table.ui_state.modal_data  ---@as PickerDialogModalData
    local modal_elements = modal_data.modal_elements
    local translations = player_table.translation_tables

    local label_warning = parent_flow.add{type="label", caption={"fp.error_message", {"fp.no_item_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = 12
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog
    modal_elements["warning_label"] = label_warning

    -- Item picker (optimized for performance, so not everything is done in the obvious way)
    local groups_per_row = MAGIC_NUMBERS.groups_per_row
    local table_item_groups = parent_flow.add{type="table", column_count=groups_per_row}
    table_item_groups.style.width = 71 * groups_per_row
    table_item_groups.style.horizontal_spacing = 0
    table_item_groups.style.vertical_spacing = 0

    local frame_filters = parent_flow.add{type="frame", style="filter_frame"}
    modal_elements["filter_frame"] = frame_filters

    local group_id_cache, group_flow_cache, subgroup_table_cache = {}, {}, {}
    modal_elements.groups = {}

    local existing_products = {}
    if not modal_data.create_factory then  -- check if this is for a new factory or not
        local factory = lib.context.get(player, "Factory")  ---@as Factory
        for product in factory:iterator() do
            existing_products[product.proto.name] = true
        end
    end

    local items_per_row = MAGIC_NUMBERS.items_per_row
    local current_item_rows, max_item_rows = 0, 0
    local current_items_in_table_count = 0
    for _, item_proto in ipairs(SORTED_ITEMS) do
        if not item_proto.hidden and not item_proto.ingredient_only then
            local group_name = item_proto.group.name
            local group_id = group_id_cache[group_name]
            local flow_subgroups  ---@type LuaGuiElement
            local subgroup_tables  ---@type table<string, table<SubgroupKey, LuaGuiElement>>

            if group_id == nil then
                local cache_count = table_size(group_id_cache) + 1
                group_id_cache[group_name] = cache_count
                group_id = cache_count

                ---@class SelectPickerItemGroupTags
                ---@field group_id integer
                local tags = {mod="fp", on_gui_click="select_picker_item_group", group_id=group_id}
                local button_group = table_item_groups.add{type="sprite-button", tags=tags,
                    sprite=("item-group/" .. group_name), style="fp_sprite-button_group_tab",
                    tooltip=item_proto.group.localised_name, mouse_button_filter={"left"}}

                -- This only exists when button_group also exists
                local scroll_pane_subgroups = frame_filters.add{type="scroll-pane", style="shallow_scroll_pane"}
                scroll_pane_subgroups.style.vertically_stretchable = true

                local frame_subgroups = scroll_pane_subgroups.add{type="frame", style="slot_button_deep_frame"}
                frame_subgroups.style.vertically_stretchable = true

                -- This flow is only really needed to set the correct vertical spacing
                flow_subgroups = frame_subgroups.add{type="flow", name="flow_group", direction="vertical"}
                flow_subgroups.style.vertical_spacing = 0
                group_flow_cache[group_id] = flow_subgroups

                modal_elements.groups[group_id] = {
                    button = button_group,
                    frame = frame_subgroups,
                    scroll_pane = scroll_pane_subgroups,
                    subgroup_tables = {}
                }
                subgroup_tables = modal_elements.groups[group_id].subgroup_tables

                -- Catch up on adding the last item flow's row count
                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_row)
                current_items_in_table_count = 0

                max_item_rows = math.max(current_item_rows, max_item_rows)
                current_item_rows = 0
            else
                flow_subgroups = group_flow_cache[group_id]
                subgroup_tables = modal_elements.groups[group_id].subgroup_tables
            end
            ---@cast flow_subgroups -nil

            local subgroup_name = item_proto.subgroup.name
            local table_subgroup = subgroup_table_cache[subgroup_name]
            local subgroup_table = nil

            if table_subgroup == nil then
                table_subgroup = flow_subgroups.add{type="table", column_count=items_per_row,
                    style="filter_slot_table"}
                table_subgroup.style.horizontally_stretchable = true
                subgroup_table_cache[subgroup_name] = table_subgroup

                subgroup_tables[subgroup_name] = {}
                subgroup_table = subgroup_tables[subgroup_name]

                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_row)
                current_items_in_table_count = 0
            else
                subgroup_table = subgroup_tables[subgroup_name]
            end

            current_items_in_table_count = current_items_in_table_count + 1

            local item_name = item_proto.name
            local existing_product = existing_products[item_name]
            local button_style = (existing_product) and "fflib_slot_button_red" or "fflib_slot_button_default"

            local name = (item_proto.temperature) and item_proto.base_name or item_name
            local elem_tooltip = (item_proto.type ~= "entity") and {type=item_proto.type, name=name} or nil

            ---@class SelectPickerItemTags
            ---@field item_id integer
            ---@field category_id integer
            ---@field enabled boolean
            local tags = {mod="fp", on_gui_click="select_picker_item", item_id=item_proto.id,
                category_id=item_proto.category_id, enabled=(existing_product == nil)}
            local button_item = table_subgroup.add{type="sprite-button", tags=tags, sprite=item_proto.sprite,
                style=button_style, tooltip=item_proto.tooltip, elem_tooltip=elem_tooltip, mouse_button_filter={"left"}}

            -- Figure out the translated name here so search doesn't have to repeat the work for every character
            local translated_name = (translations) and translations[item_proto.type][item_name] or nil
            translated_name = (translated_name) and helpers.multilingual_to_lower(translated_name) or item_name

            ---@class SubgroupKey
            local subgroup_key = {name=item_name, translated_name=translated_name}
            subgroup_table[subgroup_key] = button_item
        end
    end

    -- Catch up on addding the last item flow and groups row counts
    current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_row)
    max_item_rows = math.max(current_item_rows, max_item_rows)
    frame_filters.style.natural_height = max_item_rows * 40 + (2*12)

    -- Select the previously selected item group if possible
    local group_to_select, previous_selection = 1, player_table.ui_state.last_selected_picker_group
    if previous_selection ~= nil and modal_elements.groups[previous_selection] ~= nil then
        group_to_select = previous_selection
    end
    select_item_group(modal_data, group_to_select)
end


-- ** PICKER DIALOG **
---@param modal_data PickerDialogModalData
local function set_appropriate_focus(modal_data)
    if modal_data.amount_defined_by == "amount" then
        lib.gui.select_all(modal_data.modal_elements["item_amount_textfield"])
    else  -- "belts"/"lanes"
        lib.gui.select_all(modal_data.modal_elements["belt_amount_textfield"])
    end
end

-- Is only called when defined_by ~= "amount"
---@param modal_data PickerDialogModalData
local function sync_amounts(modal_data)
    local modal_elements = modal_data.modal_elements

    local belt_amount = lib.gui.parse_expression_field(modal_elements.belt_amount_textfield, true)
    if belt_amount == nil then
        modal_elements.item_amount_textfield.text = ""
    else
        local belt_proto = modal_data.belt_proto  ---@cast belt_proto -nil
        local throughput = belt_proto.throughput * ((modal_data.belts_or_lanes == "belts") and 1 or 0.5)
        local item_amount = belt_amount * throughput * modal_data.timescale
        modal_elements.item_amount_textfield.text = lib.format.number(item_amount, 6)
    end
end

---@param modal_data PickerDialogModalData
---@param belt_proto FPBeltPrototype?
local function set_belt_proto(modal_data, belt_proto)
    modal_data.belt_proto = belt_proto

    local modal_elements = modal_data.modal_elements
    modal_elements.item_amount_textfield.enabled = (belt_proto == nil)
    modal_elements.belt_amount_textfield.enabled = (belt_proto ~= nil)

    if belt_proto == nil then
        modal_elements.belt_choice_button.elem_value = nil
        modal_elements.belt_amount_textfield.text = ""
        modal_data.amount_defined_by = "amount"
    else
        -- Might double set the choice button, but it doesn't matter
        modal_elements.belt_choice_button.elem_value = belt_proto.name
        modal_data.amount_defined_by = modal_data.belts_or_lanes

        local item_amount = lib.gui.parse_expression_field(modal_elements.item_amount_textfield, true)
        if item_amount ~= nil then
            local throughput = belt_proto.throughput * ((modal_data.belts_or_lanes == "belts") and 1 or 0.5)
            local belt_amount = item_amount / throughput / modal_data.timescale
            modal_elements.belt_amount_textfield.text = lib.format.number(belt_amount, 6)
        end
        sync_amounts(modal_data)
    end
end

---@param modal_data PickerDialogModalData
---@param item_proto FPItemPrototype?
local function set_item_proto(modal_data, item_proto)
    local modal_elements = modal_data.modal_elements
    modal_data.item_proto = item_proto

    local item_choice_button = modal_elements.item_choice_button
    item_choice_button.sprite = (item_proto) and item_proto.sprite or nil
    if item_proto then
        local name = (item_proto.temperature) and item_proto.base_name or item_proto.name
        item_choice_button.elem_tooltip = (item_proto.type ~= "entity") and {type=item_proto.type, name=name} or nil
        item_choice_button.tooltip = item_proto.tooltip
    end

    -- Disable definition by belt for non-items
    local is_item = (item_proto and item_proto.type == "item") or false
    modal_elements.belt_choice_button.enabled = is_item
    if not is_item then set_belt_proto(modal_data, nil) end
end

---@param modal_elements table
local function update_dialog_submit_button(modal_elements)
    local item_choice_button = modal_elements.item_choice_button
    local item_amount = lib.gui.parse_expression_field(modal_elements.item_amount_textfield, true)

    local message = nil
    if item_choice_button.sprite == "" then
        message = {"fp.picker_issue_select_item"}
    elseif item_amount == nil then
        -- The item amount will be filled even if the item is defined_by ~= "amount"
        message = {"fp.picker_issue_enter_amount"}
    end

    modal_dialog.set_submit_button_state(modal_elements, (message == nil), message)
end


---@param parent_flow LuaGuiElement
---@param modal_data PickerDialogModalData
---@param item_category ItemCategory
---@param item TLProduct?
local function add_item_pane(parent_flow, modal_data, item_category, item)
    local function create_flow()
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.vertical_align = "center"
        flow.style.horizontal_spacing = 8
        flow.style.bottom_margin = 6
        return flow
    end

    local modal_elements = modal_data.modal_elements
    local defined_by = (item) and item.defined_by or "amount"
    modal_data.amount_defined_by = defined_by

    local flow_amount = create_flow()
    flow_amount.add{type="label", caption={"fp.pu_" .. item_category, 1}}

    local item_choice_button = flow_amount.add{type="sprite-button", style="fp_sprite-button_inset",
        tags={mod="fp", on_gui_click="picker_item_choice"}}
    item_choice_button.style.right_margin = 12
    modal_elements["item_choice_button"] = item_choice_button

    flow_amount.add{type="label", caption={"fp.amount"}}

    local item_amount = ""
    if item and defined_by == "amount" then
        if item.proto.special then
            if lib.is_special_power_item(item.proto.name) then
                item_amount = tostring(item.required_amount / 1e6) .. "M"
            else  -- any of the emission types
                item_amount = tostring(item.required_amount)
            end
        else
            item_amount = tostring(item.required_amount * modal_data.timescale)
        end
    end

    local textfield_amount = flow_amount.add{type="textfield", text=item_amount,
        tags={mod="fp", on_gui_text_changed="picker_item_amount", on_gui_confirmed="picker_amount",
        width=90}, tooltip={"fp.expression_textfield"}}
    textfield_amount.style.width = 90
    modal_elements["item_amount_textfield"] = textfield_amount


    local flow_belts = create_flow()
    local belts_or_lanes = {"fp.pl_" .. modal_data.belts_or_lanes:sub(1, -2), 2}
    local label = flow_belts.add{type="label", caption={"fp.amount_by", belts_or_lanes}}
    label.style.right_margin = 6

    local belt_amount = (item and defined_by ~= "amount") and tostring(item.required_amount) or ""
    local belt_width = 86
    local textfield_belts = flow_belts.add{type="textfield", text=belt_amount,
        tags={mod="fp", on_gui_text_changed="picker_belt_amount", on_gui_confirmed="picker_amount",
        width=belt_width}, tooltip={"fp.expression_textfield"}}
    textfield_belts.style.width = belt_width
    modal_elements["belt_amount_textfield"] = textfield_belts

    flow_belts.add{type="label", caption="x"}

    local choose_belt_button = flow_belts.add{type="choose-elem-button", elem_type="entity",
        tags={mod="fp", on_gui_elem_changed="picker_choose_belt"}, elem_filters=lib.gui.compile_elem_filter("belts"),
        style="fp_sprite-button_inset"}
    modal_elements["belt_choice_button"] = choose_belt_button


    local item_proto = (item) and item.proto or nil
    set_item_proto(modal_data, item_proto--[[@as FPItemPrototype?]])

    local belt_proto = (item and defined_by ~= "amount") and item.belt_proto or nil
    set_belt_proto(modal_data, belt_proto--[[@as FPBeltPrototype?]])

    if (item) then set_appropriate_focus(modal_data)
    else modal_elements.search_textfield.focus() end
    update_dialog_submit_button(modal_elements)
end


---@param player LuaPlayer
---@param tags SelectPickerItemTags
local function handle_item_pick(player, tags, _)
    local modal_data = lib.globals.modal_data(player)  ---@as PickerDialogModalData
    local item_proto = prototyper.util.find("items", tags.item_id, tags.category_id)  ---@as FPItemPrototype

    if not tags.enabled then
        lib.cursor.create_flying_text(player, {"fp.picker_already_selected", item_proto.localised_name})
        return
   end

    set_item_proto(modal_data, item_proto)  -- no need for sync in this case

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.modal_elements)
end

---@param player LuaPlayer
---@param event EventData.on_gui_elem_changed
local function handle_belt_pick(player, _, event)
    local belt_name = event.element.elem_value  ---@as string
    local belt_proto = prototyper.util.find("belts", belt_name, nil)  ---@as FPBeltPrototype

    local modal_data = lib.globals.modal_data(player)  ---@as PickerDialogModalData
    set_belt_proto(modal_data, belt_proto)  -- syncs amounts itself

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.modal_elements)
end


---@param player LuaPlayer
---@param modal_data PickerDialogModalData
local function open_picker_dialog(player, modal_data)
    local preferences = lib.globals.preferences(player)

    if modal_data.item_id then modal_data.item = OBJECT_INDEX[modal_data.item_id] end
    modal_data.timescale = preferences.timescale
    modal_data.belts_or_lanes = preferences.belts_or_lanes

    local content_frame = modal_data.modal_elements.content_frame
    content_frame.style.minimal_width = 325
    content_frame.style.bottom_padding = 6
    add_item_pane(content_frame, modal_data, modal_data.item_category, modal_data.item)

    -- The item picker only needs to show when adding a new item
    if modal_data.item_id == nil then
        local auxiliary_flow = modal_data.modal_elements.auxiliary_flow
        local picker_content_frame = auxiliary_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
        picker_content_frame.style.top_margin = 8
        add_item_picker(picker_content_frame, player)
    end
end

---@param player LuaPlayer
---@param action GUICloseAction
local function close_picker_dialog(player, action)
    local ui_state = lib.globals.ui_state(player)
    local modal_data = ui_state.modal_data  ---@as PickerDialogModalData
    local factory = lib.context.get(player, "Factory")  ---@as Factory

    if action == "submit" then
        local defined_by = modal_data.amount_defined_by
        local relevant_textfield_name = ((defined_by == "amount") and "item" or "belt") .. "_amount_textfield"
        local amount_textfield = modal_data.modal_elements[relevant_textfield_name]

        local relevant_amount = lib.gui.parse_expression_field(amount_textfield, true) or 0
        if defined_by == "amount" then
            relevant_amount = relevant_amount / modal_data.timescale
            relevant_amount = math.max(relevant_amount, MAGIC_NUMBERS.margin_of_error * 10)
        end

        if modal_data.item ~= nil then  -- ie. this is an edit
            modal_data.item.defined_by = defined_by
            modal_data.item.required_amount = relevant_amount
            modal_data.item.belt_proto = modal_data.belt_proto
        else
            local item_proto = modal_data.item_proto
            local top_level_item = TLProduct.init(item_proto)
            top_level_item.defined_by = defined_by
            top_level_item.required_amount = relevant_amount
            top_level_item.belt_proto = modal_data.belt_proto

            if modal_data.create_factory then  -- if this flag is set, create a factory to put the item into
                factory = factory_list.add_factory(player, nil, item_proto)
            end

            factory:insert(top_level_item)
            lib.gui.run_refresh(player, "factory_list")  -- for product icons
        end

        solver.update(player, factory)
        main_dialog.toggle_districts_view(player, true)
        lib.gui.run_refresh(player, "production")

    elseif action == "delete" then  ---@cast modal_data.item -nil
        factory:remove(modal_data.item)
        solver.update(player, factory)
        lib.gui.run_refresh(player, "factory_list")  -- for product icons
        lib.gui.run_refresh(player, "production")
    end

    -- Remember selected group so it can be re-applied when the dialog is re-opened
    ui_state.last_selected_picker_group = modal_data.selected_group_id
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

listeners.gui = {
    on_gui_click = {
        {
            name = "picker_item_choice",
            handler = function(player, _, _)
                local cursor_item = lib.cursor.parse_cursor_item(player)
                if cursor_item == nil then return end

                local item_proto = prototyper.util.find("items", cursor_item.name, "item")  ---@as FPItemPrototype?
                if item_proto == nil or item_proto.hidden or item_proto.ingredient_only then
                    local name = (item_proto) and item_proto.localised_name or {"fp.this"}
                    lib.cursor.create_flying_text(player, {"fp.picker_invalid_product", name})
                else
                    local factory = lib.context.get(player, "Factory")  ---@as Factory
                    local filter = {proto = item_proto}  ---@as ObjectFilter
                    local enabled = (factory:find(filter) == nil)
                    local tags = {item_id=item_proto.id, category_id=item_proto.category_id, enabled=enabled}
                    handle_item_pick(player, tags--[[@as SelectPickerItemTags]])
                end
            end
        },
        {
            name = "select_picker_item_group",
            handler = function(player, tags, _)
                ---@cast tags SelectPickerItemGroupTags
                local modal_data = lib.globals.modal_data(player)  ---@as PickerDialogModalData
                select_item_group(modal_data, tags.group_id)
            end
        },
        {
            name = "select_picker_item",
            handler = handle_item_pick
        }
    },
    on_gui_elem_changed = {
        {
            name = "picker_choose_belt",
            handler = handle_belt_pick
        }
    },
    on_gui_text_changed = {
        {
            name = "picker_item_amount",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_text_changed
                local item_amount = lib.gui.parse_expression_field(event.element, true)
                lib.gui.update_expression_field(event.element, item_amount ~= nil)

                update_dialog_submit_button(lib.globals.modal_elements(player))
            end
        },
        {
            name = "picker_belt_amount",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_text_changed
                local belt_amount = lib.gui.parse_expression_field(event.element, true)
                lib.gui.update_expression_field(event.element, belt_amount ~= nil)

                local modal_data = lib.globals.modal_data(player)  ---@as PickerDialogModalData
                sync_amounts(modal_data)  -- defined_by ~= "amount"
                update_dialog_submit_button(modal_data.modal_elements)
            end
        }
    },
    on_gui_confirmed = {
        {
            name = "picker_amount",
            handler = function(player, _, event)
                ---@cast event EventData.on_gui_confirmed
                local confirmed = lib.gui.confirm_expression_field(event.element, true)
                if confirmed then lib.gui.close_dialog(player, "submit") end
            end
        }
    }
}  ---@as GUIListenerDefinition

listeners.dialog = {
    dialog = "picker",
    metadata = function(modal_data)
        ---@cast modal_data PickerDialogModalData
        local action = (modal_data.item_id) and {"fp.edit"} or {"fp.add"}
        return {
            caption = {"", action, " ", {"fp.pl_" .. modal_data.item_category, 1}},
            search_handler_name = (not modal_data.item_id) and "search_picker_items" or nil,
            disable_scroll_pane = true,
            show_submit_button = true,
            show_delete_button = (modal_data.item_id ~= nil)
        }  ---@as ModalDialogSettings
    end,
    open = open_picker_dialog,
    close = close_picker_dialog
}

listeners.global = {
    search_picker_items = search_picker_items
}

return { listeners }

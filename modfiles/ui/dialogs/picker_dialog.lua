-- This dialog works as the product picker currently, but could also work as an ingredient picker down the line
picker_dialog = {}

-- ** ITEM PICKER **
local function select_item_group(modal_data, new_group_id)
    modal_data.selected_group_id = new_group_id

    for group_id, group_elements in pairs(modal_data.modal_elements.groups) do
        local selected_group = (group_id == new_group_id)
        group_elements.button.enabled = not selected_group
        group_elements.scroll_pane.visible = selected_group
    end
end

function SEARCH_HANDLERS.search_picker_items(player, search_term)
    local modal_data = data_util.get("modal_data", player)
    local modal_elements = modal_data.modal_elements

    -- Groups are indexed continuously, so using ipairs here is fine
    local first_visible_group_id = nil
    for group_id, group in ipairs(modal_elements.groups) do
        local any_item_visible = false

        for _, subgroup_table in pairs(group.subgroup_tables) do
            for item_data, element in pairs(subgroup_table) do
                -- Can only get to this if translations are complete, as the textfield is disabled otherwise
                local visible = (search_term == item_data.name) or
                  string.find(item_data.translated_name, search_term, 1, true)
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

local function add_item_picker(parent_flow, player)
    local player_table = data_util.get("table", player)
    local ui_state = player_table.ui_state
    local modal_elements = ui_state.modal_data.modal_elements
    local translations = player_table.translation_tables

    local label_warning = parent_flow.add{type="label", caption={"fp.error_message", {"fp.no_item_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = 12
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog
    modal_elements["warning_label"] = label_warning

    -- Item picker (optimized for performance, so not everything is done in the obvious way)
    local table_item_groups = parent_flow.add{type="table", style="filter_group_table", column_count=6}
    table_item_groups.style.width = 71 * 6
    table_item_groups.style.horizontal_spacing = 0
    table_item_groups.style.vertical_spacing = 0

    local frame_filters = parent_flow.add{type="frame", style="fp_frame_slot_table"}
    modal_elements["filter_frame"] = frame_filters

    local group_id_cache, group_flow_cache, subgroup_table_cache = {}, {}, {}
    modal_elements.groups = {}

    local existing_products = {}
    if not ui_state.modal_data.create_subfactory then  -- check if this is for a new subfactory or not
        for _, product in pairs(Subfactory.get_in_order(ui_state.context.subfactory, "Product")) do
            existing_products[product.proto.name] = true
        end
    end

    local items_per_column = 10
    local current_item_rows, max_item_rows = 0, 0
    local current_items_in_table_count = 0
    for _, item_proto in ipairs(SORTED_ITEMS) do
        if not item_proto.hidden and not item_proto.ingredient_only then
            local group_name = item_proto.group.name
            local group_id = group_id_cache[group_name]
            local flow_subgroups, subgroup_tables = nil, nil

            if group_id == nil then
                local cache_count = table_size(group_id_cache) + 1
                group_id_cache[group_name] = cache_count
                group_id = cache_count

                local button_group = table_item_groups.add{type="sprite-button", sprite=("item-group/" .. group_name),
                  tags={mod="fp", on_gui_click="select_picker_item_group", group_id=group_id},
                  style="fp_sprite-button_group_tab", tooltip=item_proto.group.localised_name,
                  mouse_button_filter={"left"}}

                -- This only exists when button_group also exists
                local scroll_pane_subgroups = frame_filters.add{type="scroll-pane",
                  style="fp_scroll-pane_slot_table"}
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
                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
                current_items_in_table_count = 0

                max_item_rows = math.max(current_item_rows, max_item_rows)
                current_item_rows = 0
            else
                flow_subgroups = group_flow_cache[group_id]
                subgroup_tables = modal_elements.groups[group_id].subgroup_tables
            end

            local subgroup_name = item_proto.subgroup.name
            local table_subgroup = subgroup_table_cache[subgroup_name]
            local subgroup_table = nil

            if table_subgroup == nil then
                table_subgroup = flow_subgroups.add{type="table", column_count=items_per_column,
                  style="filter_slot_table"}
                table_subgroup.style.horizontally_stretchable = true
                subgroup_table_cache[subgroup_name] = table_subgroup

                subgroup_tables[subgroup_name] = {}
                subgroup_table = subgroup_tables[subgroup_name]

                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
                current_items_in_table_count = 0
            else
                subgroup_table = subgroup_tables[subgroup_name]
            end

            current_items_in_table_count = current_items_in_table_count + 1

            local item_name = item_proto.name
            local existing_product = existing_products[item_name]
            local button_style = (existing_product) and "flib_slot_button_red" or "flib_slot_button_default"

            local button_item = table_subgroup.add{type="sprite-button", sprite=item_proto.sprite, style=button_style,
              tags={mod="fp", on_gui_click="select_picker_item", identifier=item_proto.identifier},
              enabled=(existing_product == nil), tooltip=item_proto.localised_name, mouse_button_filter={"left"}}

            -- Figure out the translated name here so search doesn't have to repeat the work for every character
            local translated_name = (translations) and translations[item_proto.type][item_name] or nil
            translated_name = (translated_name) and translated_name:lower() or item_name
            subgroup_table[{name=item_name, translated_name=translated_name}] = button_item
        end
    end

    -- Catch up on addding the last item flow and groups row counts
    current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
    max_item_rows = math.max(current_item_rows, max_item_rows)
    frame_filters.style.natural_height = max_item_rows * 40 + (2*12)

    select_item_group(ui_state.modal_data, 1)
end


-- ** PICKER DIALOG **
local function set_appropriate_focus(modal_data)
    if modal_data.amount_defined_by == "amount" then
        ui_util.select_all(modal_data.modal_elements["item_amount_textfield"])
    else  -- "belts"/"lanes"
        ui_util.select_all(modal_data.modal_elements["belt_amount_textfield"])
    end
end

-- Is only called when defined_by ~= "amount"
local function sync_amounts(modal_data)
    local modal_elements = modal_data.modal_elements

    local belt_amount = tonumber(modal_elements.belt_amount_textfield.text)
    if belt_amount == nil then
        modal_elements.item_amount_textfield.text = ""
    else
        local belt_proto = modal_data.belt_proto
        local throughput = belt_proto.throughput * ((modal_data.lob == "belts") and 1 or 0.5)
        local item_amount = belt_amount * throughput * modal_data.timescale
        modal_elements.item_amount_textfield.text = ui_util.format_number(item_amount, 6)
    end
end

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
        modal_data.amount_defined_by = modal_data.lob

        local item_amount = tonumber(modal_elements.item_amount_textfield.text)
        if item_amount ~= nil then
            local throughput = belt_proto.throughput * ((modal_data.lob == "belts") and 1 or 0.5)
            local belt_amount = item_amount / throughput / modal_data.timescale
            modal_elements.belt_amount_textfield.text = ui_util.format_number(belt_amount, 6)
        end
        sync_amounts(modal_data)
    end
end

local function set_item_proto(modal_data, item_proto)
    local modal_elements = modal_data.modal_elements
    modal_data.item_proto = item_proto

    local item_choice_button = modal_elements.item_choice_button
    item_choice_button.sprite = (item_proto) and item_proto.sprite or nil
    item_choice_button.tooltip = (item_proto) and item_proto.tooltip or ""

    -- Disable definition by belt for fluids
    local is_fluid = item_proto and item_proto.type == "fluid"
    modal_elements.belt_choice_button.enabled = (not is_fluid)

    -- Clear the belt-related fields if needed
    if is_fluid then set_belt_proto(modal_data, nil) end
end

local function update_dialog_submit_button(modal_elements)
    local item_choice_button = modal_elements.item_choice_button
    local item_amount_textfield = modal_elements.item_amount_textfield

    local message = nil
    if item_choice_button.sprite == "" then
        message = {"fp.picker_issue_select_item"}
    -- The item amount will be filled even if the item is defined_by ~= "amount"
    elseif tonumber(item_amount_textfield.text) == nil then
        message = {"fp.picker_issue_enter_amount"}
    end

    modal_dialog.set_submit_button_state(modal_elements, (message == nil), message)
end


local function add_item_pane(parent_flow, modal_data, item_category, item)
    local function create_flow()
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.vertical_align = "center"
        flow.style.horizontal_spacing = 8
        flow.style.bottom_margin = 6
        return flow
    end

    local modal_elements = modal_data.modal_elements
    local defined_by = (item) and item.required_amount.defined_by or "amount"
    modal_data.amount_defined_by = defined_by


    local flow_amount = create_flow()
    flow_amount.add{type="label", caption={"fp.pu_" .. item_category, 1}}

    local item_choice_button = flow_amount.add{type="sprite-button", style="fp_sprite-button_inset_tiny"}
    item_choice_button.style.right_margin = 12
    modal_elements["item_choice_button"] = item_choice_button

    flow_amount.add{type="label", caption={"fp.amount"}}

    local item_amount = (item and defined_by == "amount") and tostring(item.required_amount.amount) or ""
    local textfield_amount = flow_amount.add{type="textfield", text=item_amount,
      tags={mod="fp", on_gui_text_changed="picker_item_amount"}}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    textfield_amount.style.width = 90
    modal_elements["item_amount_textfield"] = textfield_amount


    local flow_belts = create_flow()
    flow_belts.add{type="label", caption={"fp.amount_by", {"fp.pl_" .. modal_data.lob:sub(1, -2), 2}}}

    local belt_amount = (item and defined_by ~= "amount") and tostring(item.required_amount.amount) or ""
    local textfield_belts = flow_belts.add{type="textfield", text=belt_amount,
      tags={mod="fp", on_gui_text_changed="picker_belt_amount"}}
    ui_util.setup_numeric_textfield(textfield_belts, true, false)
    textfield_belts.style.width = 85
    textfield_belts.style.left_margin = 4
    modal_elements["belt_amount_textfield"] = textfield_belts

    flow_belts.add{type="label", caption="x"}

    local belt_filter = {{filter="type", type="transport-belt"}, {filter="flag", flag="hidden", invert=true, mode="and"}}
    local choose_belt_button = flow_belts.add{type="choose-elem-button", elem_type="entity",
      tags={mod="fp", on_gui_elem_changed="picker_choose_belt"}, elem_filters=belt_filter,
      style="fp_sprite-button_inset_tiny"}
    modal_elements["belt_choice_button"] = choose_belt_button


    local item_proto = (item) and item.proto or nil
    set_item_proto(modal_data, item_proto)

    local belt_proto = (defined_by ~= "amount") and item.required_amount.belt_proto or nil
    set_belt_proto(modal_data, belt_proto)

    if (item) then set_appropriate_focus(modal_data)
    else modal_elements.search_textfield.focus() end
    update_dialog_submit_button(modal_elements)
end


local function handle_item_pick(player, tags, _)
    local modal_data = data_util.get("modal_data", player)

    local item_proto = IDENTIFIER_ITEM_MAP[tags.identifier]
    set_item_proto(modal_data, item_proto)  -- no need for sync in this case

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.modal_elements)
end

local function handle_belt_pick(player, _, event)
    local belt_name = event.element.elem_value
    local belt_proto = prototyper.util.get_new_prototype_by_name("belts", belt_name, nil)

    local modal_data = data_util.get("modal_data", player)
    set_belt_proto(modal_data, belt_proto)  -- syncs amounts itself

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.modal_elements)
end


-- ** TOP LEVEL **
picker_dialog.dialog_settings = (function(modal_data)
    local action = (modal_data.object) and {"fp.edit"} or {"fp.add"}
    return {
        caption = {"", action, " ", {"fp.pl_" .. modal_data.item_category, 1}},
        search_handler_name = (not modal_data.object) and "search_picker_items" or nil,
        show_submit_button = true,
        show_delete_button = (modal_data.object ~= nil)
    }
end)

function picker_dialog.open(player, modal_data)
    -- Create a blank subfactory if requested
    local settings = data_util.get("settings", player)
    modal_data.timescale = settings.default_timescale
    modal_data.lob = settings.belts_or_lanes

    local dialog_flow = modal_data.modal_elements.dialog_flow
    dialog_flow.style.vertical_spacing = 12

    local item_content_frame = dialog_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
    item_content_frame.style.minimal_width = 325
    item_content_frame.style.padding = {12, 12, 6, 12}
    add_item_pane(item_content_frame, modal_data, modal_data.item_category, modal_data.object)

    -- The item picker only needs to show when adding a new item
    if modal_data.object == nil then
        local picker_content_frame = dialog_flow.add{type="frame", direction="vertical", style="inside_deep_frame"}
        add_item_picker(picker_content_frame, player)
    end
end

function picker_dialog.close(player, action)
    local player_table = data_util.get("table", player)
    local modal_data = player_table.ui_state.modal_data
    local subfactory = player_table.ui_state.context.subfactory

    if action == "submit" then
        local defined_by = modal_data.amount_defined_by
        local relevant_textfield_name = ((defined_by == "amount") and "item" or "belt") .. "_amount_textfield"
        local relevant_amount = tonumber(modal_data.modal_elements[relevant_textfield_name].text)

        local req_amount = {defined_by=defined_by, amount=relevant_amount, belt_proto=modal_data.belt_proto}

        local refresh_scope = "subfactory"
        if modal_data.object ~= nil then  -- ie. this is an edit
            modal_data.object.required_amount = req_amount
        else
            local class_name = (modal_data.item_category:gsub("^%l", string.upper))
            local item_proto = modal_data.item_proto
            local top_level_item = Item.init(item_proto, class_name, 0, req_amount)

            if modal_data.create_subfactory then  -- if this flag is set, create a subfactory to put the item into
                local translations = player_table.translation_tables
                local translated_name = (translations) and translations[item_proto.type][item_proto.name] or ""
                local subfactory_name = "[img=" .. top_level_item.proto.sprite .. "] " .. translated_name
                subfactory_list.add_subfactory(player, subfactory_name)  -- sets context to new subfactory
                refresh_scope = "all"  -- need to refresh subfactory list too
            end

            Subfactory.add(subfactory, top_level_item)
        end

        calculation.update(player, subfactory)
        main_dialog.refresh(player, refresh_scope)

    elseif action == "delete" then
        Subfactory.remove(subfactory, modal_data.object)
        calculation.update(player, subfactory)
        main_dialog.refresh(player, "subfactory")
    end
end


-- ** EVENTS **
picker_dialog.gui_events = {
    on_gui_click = {
        {
            name = "select_picker_item_group",
            handler = (function(player, tags, _)
                local modal_data = data_util.get("modal_data", player)
                select_item_group(modal_data, tags.group_id)
            end)
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
            handler = (function(player, _, _)
                local modal_data = data_util.get("modal_data", player)
                update_dialog_submit_button(modal_data.modal_elements)
            end)
        },
        {
            name = "picker_belt_amount",
            handler = (function(player, _, _)
                local modal_data = data_util.get("modal_data", player)
                sync_amounts(modal_data)  -- defined_by ~= "amount"
                update_dialog_submit_button(modal_data.modal_elements)
            end)
        }
    }
}

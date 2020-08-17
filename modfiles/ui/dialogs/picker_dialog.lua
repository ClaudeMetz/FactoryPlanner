-- This dialog works as the product picker currently, but could also work as an ingredient picker down the line
picker_dialog = {}

-- ** ITEM PICKER **
local function select_item_group(modal_data, new_group_id)
    modal_data.selected_group_id = new_group_id

    for group_id, group_elements in pairs(modal_data.ui_elements.groups) do
        local selected_group = (group_id == new_group_id)
        group_elements.button.style = (selected_group) and "fp_sprite-button_rounded_dark" or "rounded_button"
        group_elements.button.enabled = not selected_group
        group_elements.scroll_pane.visible = selected_group
    end
end

local function focus_searchfield(player)
    local ui_state = data_util.get("ui_state", player)
    if ui_state.modal_dialog_type == "picker" and ui_state.modal_data.object == nil then
        ui_util.select_all(ui_state.modal_data.ui_elements.search_textfield)
    end
end

local function search_items(player, searchfield)
    local search_term = searchfield.text:gsub("^%s*(.-)%s*$", "%1"):lower()
    local modal_data = data_util.get("modal_data", player)
    local ui_elements = modal_data.ui_elements

    -- Groups are indexed continuously, so using ipairs here is fine
    local first_visible_group_id = nil
    for group_id, group in ipairs(ui_elements.groups) do
        local any_item_visible = false

        for _, subgroup_table in pairs(group.subgroup_tables) do
            for item_name, element in pairs(subgroup_table) do
                local visible = string.find(item_name, search_term, 1, true)
                element.visible = visible
                any_item_visible = any_item_visible or visible
            end
        end

        group.button.visible = any_item_visible
        first_visible_group_id = first_visible_group_id or ((any_item_visible) and group_id or nil)
    end

    local any_result_found = (first_visible_group_id ~= nil)
    ui_elements.warning_label.visible = not any_result_found
    ui_elements.filter_frame.visible = any_result_found

    if first_visible_group_id ~= nil then
        local selected_group_id = modal_data.selected_group_id
        local is_selected_group_visible = ui_elements.groups[selected_group_id].button.visible
        local group_id_to_select = is_selected_group_visible and selected_group_id or first_visible_group_id
        select_item_group(modal_data, group_id_to_select)
    end
end

-- Custom titlebar construction to be able to integrate a search field into it
local function fill_titlebar(modal_data)
    local flow_titlebar = modal_data.ui_elements.titlebar_flow

    flow_titlebar.add{type="label", caption={"fp.two_word_title", {"fp.add"},
      {"fp.pl_" .. modal_data.item_category, 1}}, style="frame_title"}

    local drag_handle = flow_titlebar.add{type="empty-widget", style="flib_titlebar_drag_handle"}
    drag_handle.drag_target = modal_data.ui_elements.frame

    local searchfield = flow_titlebar.add{type="textfield", name="fp_textfield_picker_search",
      style="search_popup_textfield"}
    ui_util.setup_textfield(searchfield)
    searchfield.style.width = 180
    searchfield.style.margin = {-3, 4, 0, 0}
    searchfield.focus()
    modal_data.ui_elements["search_textfield"] = searchfield

    flow_titlebar.add{type="sprite-button", name="fp_sprite-button_picker_search", sprite="utility/search_white",
      tooltip={"fp.search_button_tt"}, style="frame_action_button", mouse_button_filter={"left"}}
end

local function add_item_picker(parent_flow, player)
    local ui_state = data_util.get("ui_state", player)
    local ui_elements = ui_state.modal_data.ui_elements

    local label_warning = parent_flow.add{type="label", caption={"fp.error_message", {"fp.no_item_found"}}}
    label_warning.style.font = "heading-2"
    label_warning.style.margin = 12
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog
    ui_elements["warning_label"] = label_warning

    -- Item picker (optimized for performance, so not everything is done in the obvious way)
    local frame_item_groups = parent_flow.add{type="frame", direction="vertical",
      style="fp_frame_deep_slots_crafting_groups"}
    local table_item_groups = frame_item_groups.add{type="table", column_count=6}
    table_item_groups.style.width = 442
    table_item_groups.style.horizontal_spacing = 0
    table_item_groups.style.vertical_spacing = 0

    local frame_filters = parent_flow.add{type="frame", style="slot_button_deep_frame"}
    frame_filters.style.top_margin = 8
    ui_elements["filter_frame"] = frame_filters

    local group_id_cache, group_flow_cache, subgroup_table_cache = {}, {}, {}
    ui_elements.groups = {}

    local existing_products = {}
    for _, product in pairs(Subfactory.get_in_order(ui_state.context.subfactory, "Product")) do
        existing_products[product.proto.name] = true
    end

    local items_per_column = 10
    local current_item_rows, max_item_rows = 0, 0
    local current_items_in_table_count = 0
    for _, item_proto in ipairs(SORTED_ITEMS) do
        -- TODO this ingredient_only business only works on product pickers
        if not item_proto.hidden and not item_proto.ingredient_only then
            local group_name = item_proto.group.name
            local group_id = group_id_cache[group_name]
            local flow_subgroups, subgroup_tables = nil, nil

            if group_id == nil then
                local cache_count = table_size(group_id_cache) + 1
                group_id_cache[group_name] = cache_count
                group_id = cache_count

                local button_group = table_item_groups.add{type="sprite-button", name="fp_sprite-button_item_group_"
                  .. group_id, sprite=("item-group/" .. group_name), tooltip=item_proto.group.localised_name,
                  mouse_button_filter={"left"}}  -- style set by item group selection
                button_group.style.minimal_width = 0
                button_group.style.height = 64
                button_group.style.padding = 2
                button_group.style.horizontally_stretchable = true

                -- This only exists when button_group also exists
                local scroll_pane_subgroups = frame_filters.add{type="scroll-pane",
                  style="fp_scroll_pane_inside_content_frame_bare"}

                -- This flow is only really needed to set the correct vertical spacing
                flow_subgroups = scroll_pane_subgroups.add{type="flow", name="flow_group", direction="vertical"}
                flow_subgroups.style.vertical_spacing = 0
                group_flow_cache[group_id] = flow_subgroups

                ui_elements.groups[group_id] = {
                    button = button_group,
                    scroll_pane = scroll_pane_subgroups,
                    subgroup_tables = {}
                }
                subgroup_tables = ui_elements.groups[group_id].subgroup_tables

                -- Catch up on adding the last item flow's row count
                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
                current_items_in_table_count = 0

                max_item_rows = math.max(current_item_rows, max_item_rows)
                current_item_rows = 0
            else
                flow_subgroups = group_flow_cache[group_id]
                subgroup_tables = ui_elements.groups[group_id].subgroup_tables
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

            local existing_product = existing_products[item_proto.name]
            local button_style = (existing_product) and "flib_slot_button_red" or "flib_slot_button_default"

            local button_item = table_subgroup.add{type="sprite-button", name="fp_button_item_pick_"
              .. item_proto.identifier, sprite=item_proto.sprite, enabled=(existing_product == nil),
              tooltip=item_proto.localised_name, style=button_style, mouse_button_filter={"left"}}

            -- Ignores item types, so if one subgroup has both a fluid and an item of the same name,
            -- it'll only catch one. Let's see how long it takes until someone runs into this.
            subgroup_table[item_proto.name] = button_item
        end
    end

    -- Catch up on addding the last item flow and groups row counts
    current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
    max_item_rows = math.max(current_item_rows, max_item_rows)
    frame_filters.style.natural_height = max_item_rows * 40

    select_item_group(ui_state.modal_data, 1)
end


-- ** PICKER DIALOG **
local function set_appropriate_focus(modal_data)
    if modal_data.amount_defined_by == "amount" then
        ui_util.select_all(modal_data.ui_elements["item_amount_textfield"])
    else  -- "belts"/"lanes"
        ui_util.select_all(modal_data.ui_elements["belt_amount_textfield"])
    end
end

-- Is only called when defined_by ~= "amount"
local function sync_amounts(modal_data)
    local ui_elements = modal_data.ui_elements

    local belt_amount = tonumber(ui_elements.belt_amount_textfield.text)
    if belt_amount == nil then
        ui_elements.item_amount_textfield.text = ""
    else
        local belt_proto = modal_data.belt_proto
        local throughput = belt_proto.throughput * ((modal_data.lob == "belts") and 1 or 0.5)
        local item_amount = belt_amount * throughput * modal_data.timescale
        ui_elements.item_amount_textfield.text = ui_util.format_number(item_amount, 6)
    end
end

local function set_belt_proto(modal_data, belt_proto)
    modal_data.belt_proto = belt_proto

    local ui_elements = modal_data.ui_elements
    ui_elements.item_amount_textfield.enabled = (belt_proto == nil)
    ui_elements.belt_amount_textfield.enabled = (belt_proto ~= nil)

    if belt_proto == nil then
        ui_elements.belt_choice_button.elem_value = nil
        ui_elements.belt_amount_textfield.text = ""
        modal_data.amount_defined_by = "amount"
    else
        -- Might double set the choice button, but it doesn't matter
        ui_elements.belt_choice_button.elem_value = belt_proto.name
        modal_data.amount_defined_by = modal_data.lob

        local item_amount = tonumber(ui_elements.item_amount_textfield.text)
        if item_amount ~= nil then
            local throughput = belt_proto.throughput * ((modal_data.lob == "belts") and 1 or 0.5)
            local belt_amount = item_amount / throughput / modal_data.timescale
            ui_elements.belt_amount_textfield.text = ui_util.format_number(belt_amount, 6)
        end
        sync_amounts(modal_data)
    end
end

local function set_item_proto(modal_data, item_proto)
    local ui_elements = modal_data.ui_elements
    modal_data.item_proto = item_proto

    local item_choice_button = ui_elements.item_choice_button
    item_choice_button.sprite = (item_proto) and item_proto.sprite or nil
    item_choice_button.tooltip = (item_proto) and item_proto.tooltip or nil

    -- Disable definition by belt for fluids
    local is_fluid = item_proto and item_proto.type == "fluid"
    ui_elements.belt_choice_button.enabled = (not is_fluid)

    -- Clear the belt-related fields if needed
    if is_fluid then set_belt_proto(modal_data, nil) end
end

local function update_dialog_submit_button(ui_elements)
    local item_choice_button = ui_elements.item_choice_button
    local item_amount_textfield = ui_elements.item_amount_textfield

    local message = nil
    if item_choice_button.sprite == "" then
        message = {"fp.picker_issue_select_item"}
    -- The item amount will be filled even if the item is defined_by ~= "amount"
    elseif tonumber(item_amount_textfield.text) == nil then
        message = {"fp.picker_issue_enter_amount"}
    end

    modal_dialog.set_submit_button_state(ui_elements, (message == nil), message)
end


local function add_item_pane(parent_flow, modal_data, item_category, item)
    local function create_flow()
        local flow = parent_flow.add{type="flow", direction="horizontal"}
        flow.style.vertical_align = "center"
        flow.style.horizontal_spacing = 8
        flow.style.bottom_margin = 6
        return flow
    end

    local ui_elements = modal_data.ui_elements
    local defined_by = (item) and item.required_amount.defined_by or "amount"
    modal_data.amount_defined_by = defined_by


    local flow_amount = create_flow()
    flow_amount.add{type="label", caption={"fp.pu_" .. item_category, 1}}

    local item_choice_button = flow_amount.add{type="sprite-button", style="fp_sprite-button_inset_tiny"}
    item_choice_button.style.right_margin = 12
    ui_elements["item_choice_button"] = item_choice_button

    flow_amount.add{type="label", caption={"fp.amount"}}

    local item_amount = (item and defined_by == "amount") and item.required_amount.amount or nil
    local textfield_amount = flow_amount.add{type="textfield", name="fp_textfield_picker_item_amount", text=item_amount}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    textfield_amount.style.width = 90
    ui_elements["item_amount_textfield"] = textfield_amount


    local flow_belts = create_flow()
    flow_belts.add{type="label", caption={"fp.amount_by", {"fp.pl_" .. modal_data.lob:sub(1, -2), 2}}}

    local belt_amount = (item and defined_by ~= "amount") and item.required_amount.amount or ""
    local textfield_belts = flow_belts.add{type="textfield", name="fp_textfield_picker_belt_amount", text=belt_amount}
    ui_util.setup_numeric_textfield(textfield_belts, true, false)
    textfield_belts.style.width = 85
    textfield_belts.style.left_margin = 4
    ui_elements["belt_amount_textfield"] = textfield_belts

    flow_belts.add{type="label", caption="x"}

    local choose_belt_button = flow_belts.add{type="choose-elem-button", name="fp_choose-elem-button_picker_belt",
      elem_type="entity", elem_filters={{filter="type", type="transport-belt"}}, style="fp_sprite-button_inset_tiny"}
    ui_elements["belt_choice_button"] = choose_belt_button


    local item_proto = (item) and item.proto or nil
    set_item_proto(modal_data, item_proto)

    local belt_proto = (defined_by ~= "amount") and item.required_amount.belt_proto or nil
    set_belt_proto(modal_data, belt_proto)

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(ui_elements)
end


local function handle_item_pick(player, element)
    local item_identifier = string.gsub(element.name, "fp_button_item_pick_", "")
    local item_proto = IDENTIFIER_ITEM_MAP[item_identifier]

    local modal_data = data_util.get("modal_data", player)
    set_item_proto(modal_data, item_proto)  -- no need for sync in this case

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.ui_elements)
end

local function handle_belt_pick(player, element)
    local belt_name = element.elem_value
    local belt_proto = prototyper.util.get_new_prototype_by_name("belts", belt_name, nil)

    local modal_data = data_util.get("modal_data", player)
    set_belt_proto(modal_data, belt_proto)  -- syncs amounts itself

    set_appropriate_focus(modal_data)
    update_dialog_submit_button(modal_data.ui_elements)
end


-- ** TOP LEVEL **
picker_dialog.dialog_settings = (function(modal_data) return {
    caption = (modal_data.object) and {"fp.two_word_title", {"fp.edit"},
      {"fp.pl_" .. modal_data.item_category, 1}} or nil,
    force_auto_center = true
} end)

picker_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_item_group_%d+$",
            handler = (function(player, element, _)
                local modal_data = data_util.get("modal_data", player)
                local group_id = tonumber(string.match(element.name, "%d+"))
                select_item_group(modal_data, group_id)
            end)
        },
        {
            pattern = "^fp_button_item_pick_%d+_%d+$",
            handler = (function(player, element, _)
                handle_item_pick(player, element)
            end)
        },
        {
            name = "fp_sprite-button_picker_search",
            handler = (function(player, _, _)
                focus_searchfield(player)
            end)
        }
    },
    on_gui_elem_changed = {
        {
            name = "fp_choose-elem-button_picker_belt",
            handler = (function(player, element)
                handle_belt_pick(player, element)
            end)
        }
    },
    on_gui_text_changed = {
        {
            name = "fp_textfield_picker_search",
            handler = (function(player, element)
                search_items(player, element)
            end)
        },
        {
            name = "fp_textfield_picker_item_amount",
            handler = (function(player, _)
                local modal_data = data_util.get("modal_data", player)
                update_dialog_submit_button(modal_data.ui_elements)
            end)
        },
        {
            name = "fp_textfield_picker_belt_amount",
            handler = (function(player, _)
                local modal_data = data_util.get("modal_data", player)
                sync_amounts(modal_data)  -- defined_by ~= "amount"
                update_dialog_submit_button(modal_data.ui_elements)
            end)
        }
    }
}

picker_dialog.misc_events = {
    fp_focus_searchfield = (function(player, _)
        focus_searchfield(player)
    end)
}

function picker_dialog.open(player, modal_data)
    modal_data.timescale = data_util.get("context", player).subfactory.timescale
    modal_data.lob = data_util.get("settings", player).belts_or_lanes

    local dialog_flow = modal_data.ui_elements.dialog_flow
    dialog_flow.style.vertical_spacing = 12

    local function add_content_frame()
        local content_frame = dialog_flow.add{type="frame", direction="vertical", style="inside_shallow_frame"}
        content_frame.style.vertically_stretchable = true
        return content_frame
    end

    local item_content_frame = add_content_frame()
    item_content_frame.style.minimal_width = 325
    item_content_frame.style.padding = {12, 12, 6, 12}
    add_item_pane(item_content_frame, modal_data, modal_data.item_category, modal_data.object)

    -- The item picker only needs to show when adding a new item
    if modal_data.object == nil then
        fill_titlebar(modal_data)
        add_item_picker(add_content_frame(), player)
    end
end

function picker_dialog.close(player, action)
    local modal_data = data_util.get("modal_data", player)
    local subfactory = data_util.get("context", player).subfactory
    local item = modal_data.object

    if action == "submit" then
        local defined_by = modal_data.amount_defined_by
        local relevant_textfield_name = ((defined_by == "amount") and "item" or "belt") .. "_amount_textfield"
        local relevant_amount = tonumber(modal_data.ui_elements[relevant_textfield_name].text)

        local req_amount = {defined_by=defined_by, amount=relevant_amount, belt_proto=modal_data.belt_proto}

        if item == nil then  -- add item if it doesn't exist (ie. this is not an edit)
            local item_category = modal_data.item_category  -- this is in lowercase
            local class_name = item_category:sub(1,1):upper() .. item_category:sub(2)

            local top_level_item = Item.init_by_proto(modal_data.item_proto, class_name, 0, req_amount)
            Subfactory.add(subfactory, top_level_item)
        else
            item.required_amount = req_amount
        end

        calculation.update(player, subfactory, true)

    elseif action == "delete" then
        Subfactory.remove(subfactory, item)

        -- Remove useless recipes after a product has been deleted
        calculation.update(player, subfactory, false)
        Subfactory.remove_useless_lines(subfactory)

        ui_util.context.set_floor(player, Subfactory.get(subfactory, "Floor", 1))
        calculation.update(player, subfactory, true)
    end
end
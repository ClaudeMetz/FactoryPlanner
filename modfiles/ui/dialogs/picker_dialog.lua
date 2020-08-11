-- This dialog works as the product picker currently, but could also work as an ingredient picker down the line
picker_dialog = {}

-- ** ITEM PICKER **
local function select_item_group(ui_elements, new_group_id)
    for group_id, group_elements in pairs(ui_elements.groups) do
        local selected_group = (group_id == new_group_id)
        group_elements.button.style = (selected_group) and "fp_sprite-button_rounded_dark" or "rounded_button"
        group_elements.enabled = selected_group
        group_elements.scroll_pane.visible = selected_group
    end
end

local function handle_item_pick(player, element)
    local item_identifier = string.gsub(element.name, "fp_button_item_pick_", "")
    local item_proto = identifier_item_map[item_identifier]

    local modal_data = data_util.get("modal_data", player)
    modal_data.item_proto = item_proto

    local item_choice_button = modal_data.ui_elements.item_choice_button
    item_choice_button.sprite = item_proto.sprite
    item_choice_button.tooltip = item_proto.tooltip
end

local function add_item_picker(parent_flow, player)
    local label_warning = parent_flow.add{type="label", caption={"fp.error_message", {"fp.no_item_found"}}}
    label_warning.style.font = "fp-font-bold-16p"
    label_warning.visible = false  -- There can't be a warning upon first opening of the dialog

    -- Item picker (optimized for performance, so not everything is done in the obvious way)
    local frame_item_groups = parent_flow.add{type="frame", direction="vertical",
      style="fp_frame_deep_slots_crafting_groups"}
    local table_item_groups = frame_item_groups.add{type="table", column_count=6}
    table_item_groups.style.horizontal_spacing = 0
    table_item_groups.style.vertical_spacing = 0

    local frame_filters = parent_flow.add{type="frame", style="slot_button_deep_frame"}
    frame_filters.style.width = 442
    frame_filters.style.top_margin = 8

    local group_id_cache, group_flow_cache, subgroup_table_cache = {}, {}, {}
    local ui_elements = data_util.get("ui_elements", player)
    ui_elements.groups = {}

    local existing_products, ui_state = {}, data_util.get("ui_state", player)
    for _, product in pairs(Subfactory.get_in_order(ui_state.context.subfactory, "Product")) do
        existing_products[product.proto.name] = true
    end

    local items_per_column = 10
    local current_item_rows, max_item_rows = 0, 0
    local current_items_in_table_count = 0
    for _, item_proto in ipairs(sorted_items) do  -- global variable
        -- TODO this ingredient_only business only works on product pickers
        if not item_proto.hidden and not item_proto.ingredient_only then
            local group_name = item_proto.group.name
            local group_id = group_id_cache[group_name]
            local flow_subgroups = nil

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
                flow_subgroups = scroll_pane_subgroups.add{type="flow", direction="vertical"}
                flow_subgroups.style.vertical_spacing = 0
                group_flow_cache[group_id] = flow_subgroups
                ui_elements.groups[group_id] = {button=button_group, scroll_pane=scroll_pane_subgroups}

                -- Catch up on adding the last item flow's row count
                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
                current_items_in_table_count = 0

                max_item_rows = math.max(current_item_rows, max_item_rows)
                current_item_rows = 0
            else
                flow_subgroups = group_flow_cache[group_id]
            end

            local subgroup_name = item_proto.subgroup.name
            local table_subgroup = subgroup_table_cache[subgroup_name]

            if table_subgroup == nil then
                table_subgroup = flow_subgroups.add{type="table", column_count=items_per_column,
                  style="filter_slot_table"}
                table_subgroup.style.horizontally_stretchable = true
                subgroup_table_cache[subgroup_name] = table_subgroup

                current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
                current_items_in_table_count = 0
            end

            current_items_in_table_count = current_items_in_table_count + 1

            local existing_product = existing_products[item_proto.name]
            local button_style = (existing_product) and "flib_slot_button_red" or "flib_slot_button_default"

            table_subgroup.add{type="sprite-button", name="fp_button_item_pick_"
              .. item_proto.identifier, sprite=item_proto.sprite, enabled=(existing_product == nil),
              tooltip=item_proto.localised_name, style=button_style, mouse_button_filter={"left"}}
        end
    end

    -- Catch up on addding the last item flow and groups row counts
    current_item_rows = current_item_rows + math.ceil(current_items_in_table_count / items_per_column)
    max_item_rows = math.max(current_item_rows, max_item_rows)

    -- Determine the highest item group panel and set them all to that height
    local picker_flow_height = max_item_rows * 40
    for _, flow_group in pairs(group_flow_cache) do
        -- TODO this should really set the scroll pane height, but that glitches out for some reason
        flow_group.style.height = picker_flow_height
    end

    select_item_group(ui_elements, 1)
end


-- ** PICKER DIALOG **
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

    local sprite = (item) and item.proto.sprite or nil
    local tooltip = (item) and item.proto.localised_name or ""
    local item_choice_button = flow_amount.add{type="sprite-button", sprite=sprite, tooltip=tooltip,
      style="fp_sprite-button_inset_tiny"}
    item_choice_button.style.right_margin = 12
    modal_data.item_proto = (item) and item.proto or nil
    ui_elements["item_choice_button"] = item_choice_button

    flow_amount.add{type="label", caption={"fp.amount"}}

    local item_amount = (item and defined_by == "amount") and item.required_amount.amount or nil
    local textfield_amount = flow_amount.add{type="textfield", name="fp_textfield_picker_item_amount", text=item_amount}
    ui_util.setup_numeric_textfield(textfield_amount, true, false)
    textfield_amount.style.width = 90
    ui_elements["item_amount_textfield"] = textfield_amount


    local flow_belts = create_flow()
    flow_belts.add{type="label", caption={"fp.amount_by", {"fp.pl_" .. modal_data.lob:sub(1, -2), 2}}}

    local belt_amount = (defined_by ~= "amount") and item.required_amount.amount or ""
    local textfield_belts = flow_belts.add{type="textfield", name="fp_textfield_picker_lob_amount", text=belt_amount}
    ui_util.setup_numeric_textfield(textfield_belts, true, false)
    textfield_belts.style.width = 85
    textfield_belts.style.left_margin = 4
    ui_elements["belt_amount_textfield"] = textfield_belts

    flow_belts.add{type="label", caption="x"}

    local elem_filters = {{filter="type", type="transport-belt"}}
    local belt_name = (defined_by ~= "amount") and item.required_amount.belt_proto.name or nil
    local choose_belt_button = flow_belts.add{type="choose-elem-button", name="fp_choose-elem-button_picker_belt",
      elem_type="entity", entity=belt_name, elem_filters=elem_filters, style="fp_sprite-button_inset_tiny"}
    ui_elements["belt_choice_button"] = choose_belt_button
    modal_data.belt_proto = prototyper.util.get_new_prototype_by_name("belts", belt_name, nil)
end

-- ** TOP LEVEL **
picker_dialog.dialog_settings = (function(modal_data) return {
    caption = {"fp.two_word_title", ((modal_data.object) and {"fp.edit"} or {"fp.add"}),
      {"fp.pl_" .. modal_data.item_category, 1}},
    force_auto_center = true
} end)

picker_dialog.gui_events = {
    on_gui_click = {
        {
            pattern = "^fp_sprite%-button_item_group_%d+$",
            handler = (function(player, element, _)
                local ui_elements = data_util.get("ui_elements", player)
                local group_id = tonumber(string.match(element.name, "%d+"))
                select_item_group(ui_elements, group_id)
            end)
        },
        {
            pattern = "^fp_button_item_pick_%d+_%d+$",
            handler = (function(player, element, _)
                handle_item_pick(player, element)
            end)
        }
    }
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
    item_content_frame.style.padding = {12, 12, 6, 12}
    add_item_pane(item_content_frame, modal_data, modal_data.item_category, modal_data.object)

    -- The item picker only needs to show when adding a new item
    if modal_data.object == nil then
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
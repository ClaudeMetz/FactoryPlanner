-- This dialog works as the product picker currently, but could also work as an ingredient picker down the line
picker_dialog = {}

-- ** LOCAL UTIL **
local function add_item_pane(parent_flow, modal_data, item_type, item)
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
    flow_amount.add{type="label", caption={"fp.pu_" .. item_type, 1}}

    local elem_type = (item) and item.proto.type or "item"  -- item-category being the 'default'
    local item_name = (item) and item.proto.name or nil
    local choose_item_button = flow_amount.add{type="choose-elem-button", name="fp_choose-elem-button_picker_item",
      elem_type=elem_type, style="fp_sprite-button_inset_tiny"}
    choose_item_button.style.right_margin = 12
    choose_item_button.elem_value = item_name  -- more easily set after button creation
    --choose_item_button.locked = true
    ui_elements["item_choice_button"] = choose_item_button
    modal_data.item_proto = prototyper.util.get_new_prototype_by_name("items", item_name, elem_type)

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
      {"fp.pl_" .. modal_data.item_type, 1}},
    create_content_frame = true,
    force_auto_center = true
} end)

function picker_dialog.open(player, modal_data)
    modal_data.timescale = data_util.get("context", player).subfactory.timescale
    modal_data.lob = data_util.get("settings", player).belts_or_lanes

    --[[ local item_pane_parent = (modal_data.object) and ui_elements.content_frame
    or ui_elements.content_frame.add{type="frame", style="fp_frame_bordered_stretch"}
    item_pane_parent.style.padding = 8 ]]
    add_item_pane(modal_data.ui_elements.content_frame, modal_data, modal_data.item_type, modal_data.object)
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
            local item_type = modal_data.item_type  -- this is in lowercase
            local class_name = item_type:sub(1,1):upper() .. item_type:sub(2)

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
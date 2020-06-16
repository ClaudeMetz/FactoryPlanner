require("ui.elements.item_picker")

-- Handles populating the item picker dialog
function open_product_dialog(flow_modal_dialog, modal_data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local product = modal_data.product

    flow_modal_dialog.parent.caption = (product == nil) and {"fp.add_product"} or {"fp.edit_product"}
    flow_modal_dialog.style.padding = 8
    refresh_product_bar(flow_modal_dialog, product)
    local picker_flow = item_picker.create(flow_modal_dialog)

    if product == nil then
        item_picker.select_group(picker_flow, "1")  -- select the first item group by default
        item_picker.reset_searchfield(picker_flow)
        item_picker.filter(picker_flow, "", true)
        picker_flow.visible = true
    else
        picker_flow.visible = false
    end

    -- Not sure why this is necessary, but it goes wonky otherwise
    -- This is only been necessary when a choose-elem-button is present, weirdly
    flow_modal_dialog.parent.force_auto_center()
end

-- Handles closing of the item picker dialog
function close_product_dialog(flow_modal_dialog, action, data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local product = ui_state.modal_data.product

    if action == "submit" then
        local modal_data = ui_state.modal_data
        local req_amount = {
            defined_by = modal_data.amount_defined_by,
            amount = tonumber(data[modal_data.amount_defined_by .. "_amount"]),
            belt_proto = modal_data.belt_proto
        }

        if product == nil then  -- add product if it doesn't exist (ie. this is not an edit)
            local top_level_item = Item.init_by_proto(ui_state.modal_data.selected_item, "Product", 0, req_amount)
            Subfactory.add(subfactory, top_level_item)
        else
            product.required_amount = req_amount
        end

    elseif action == "delete" then  -- delete can only be pressed if product ~= nil
        Subfactory.remove(subfactory, product)

        -- Remove useless recipes after a product has been deleted
        calculation.update(player, subfactory, false)
        Subfactory.remove_useless_lines(subfactory)
        ui_util.context.set_floor(player, Subfactory.get(subfactory, "Floor", 1))
    end

    calculation.update(player, subfactory, true)
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_product_condition_instructions()
    return {
        data = {
            item_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_product_bar"]["flow_product_amount"]["sprite-button_product"].sprite end),
            amount_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_product_bar"]["flow_product_amount"]["fp_textfield_product_amount"].text end),
            belts_amount = (function(flow_modal_dialog)
                local flow = flow_modal_dialog["flow_product_bar"]["flow_product_belts"]
                return (flow ~= nil) and flow["fp_textfield_product_belts"].text or nil
            end),
            lanes_amount = (function(flow_modal_dialog)
                local flow = flow_modal_dialog["flow_product_bar"]["flow_product_lanes"]
                return (flow ~= nil) and flow["fp_textfield_product_lanes"]
                .text or nil
            end)
        },
        conditions = {
            [1] = {
                label = {"fp.product_instruction_1"},
                check = (function(data) return (data.item_sprite == "" or (tonumber(data.amount_amount) == nil
                  and tonumber(data.belts_amount) == nil)) end),
                refocus = (function(flow, data)
                    if data.item_sprite == "" then ui_util.select_all(flow["flow_item_picker"]["table_search_bar"]
                      ["fp_textfield_item_picker_search_bar"])
                    else ui_util.select_all(flow["flow_product_bar"]["flow_product_amount"]
                      ["fp_textfield_product_amount"]) end
                end),
                show_on_edit = true
            }
        }
    }
end


-- Adds a row containing the picked item and it's required_amount
function refresh_product_bar(flow_modal_dialog, product)
    local player = game.get_player(flow_modal_dialog.player_index)
    local modal_data = get_modal_data(player)
    modal_data.timescale = get_context(player).subfactory.timescale -- needed for calculations
    modal_data.lanes_or_belts = get_settings(player).belts_or_lanes

    local item_sprite, item_tooltip, belt_name
    local item_amount, belt_amount = "", ""
    if product ~= nil then  -- Adjustments if the product is being edited
        modal_data.selected_item = product.proto
        modal_data.amount_defined_by = product.required_amount.defined_by
        modal_data.belt_proto = product.required_amount.belt_proto

        item_sprite = product.proto.sprite
        item_tooltip = product.proto.localised_name

        belt_name = (modal_data.belt_proto ~= nil) and modal_data.belt_proto.name or nil

        if modal_data.amount_defined_by == "amount" then
            item_amount = ui_util.format_number(product.required_amount.amount, 8)
        else  -- defined_by == "belts"/"lanes"
            belt_amount = ui_util.format_number(product.required_amount.amount, 6)
        end
    else
        -- Set a default defined_by for new products
        modal_data.amount_defined_by = "amount"
    end

    local flow_product_bar = flow_modal_dialog["flow_product_bar"]
    if flow_product_bar == nil then
        flow_product_bar = flow_modal_dialog.add{type="flow", name="flow_product_bar", direction="vertical"}
        flow_product_bar.style.vertical_spacing = 8
    end
    flow_product_bar.clear()

    -- Product choice and amount
    local flow_product_amount = flow_product_bar.add{type="flow", name="flow_product_amount", direction="horizontal"}
    flow_product_amount.style.horizontal_spacing = 8
    flow_product_amount.style.vertical_align = "center"

    flow_product_amount.add{type="label", caption={"fp.product"}}
    local button = flow_product_amount.add{type="sprite-button", name="sprite-button_product", sprite=item_sprite,
      tooltip=item_tooltip, style="fp_sprite-button_choose_elem"}
    button.style.right_margin = 14

    flow_product_amount.add{type="label", caption={"fp.amount"}}
    local textfield_item = flow_product_amount.add{type="textfield", name="fp_textfield_product_amount",
      text=item_amount}
    ui_util.setup_numeric_textfield(textfield_item, true, false)
    textfield_item.style.width = 80

    -- Product amount specification by belt
    local lob = modal_data.lanes_or_belts
    local flow_product_belts = flow_product_bar.add{type="flow", name=("flow_product_" .. lob),
      direction="horizontal"}
    flow_product_belts.style.vertical_align = "center"

    local label_belt_amount = flow_product_belts.add{type="label", caption={"fp.amount_by", {"fp." .. lob}}}
    label_belt_amount.style.right_margin = 10

    local textfield_belt = flow_product_belts.add{type="textfield", name=("fp_textfield_product_" .. lob),
      text=belt_amount, enabled=(modal_data.belt_proto~=nil)}
    ui_util.setup_numeric_textfield(textfield_belt, true, false)
    textfield_belt.style.width = 65

    local label_X = flow_product_belts.add{type="label", caption="X"}
    label_X.style.margin = {0, 3}

    local choose_elem_button = flow_product_belts.add{type="choose-elem-button", elem_type="entity",
      name="fp_choose-elem-button_product_belts", style="fp_sprite-button_choose_elem"}
    choose_elem_button.elem_filters = {{filter="type", type="transport-belt"}}
    choose_elem_button.elem_value = belt_name  -- needs to be set after the filter

    adjust_for_item_type(flow_product_bar, modal_data)
    update_product_amounts(flow_product_bar, modal_data)
    set_appropriate_amount_focus(flow_product_bar, modal_data)

    return flow_product_bar
end


-- Adjusts the dialog according to the product type, disallowing fluids to be set by belt
function adjust_for_item_type(flow_product_bar, modal_data)
    local item_proto = modal_data.selected_item

    if item_proto ~= nil then
        local lob = modal_data.lanes_or_belts
        local choose_elem_button = flow_product_bar["flow_product_" .. lob]["fp_choose-elem-button_product_belts"]
        choose_elem_button.enabled = (item_proto.type == "item")

        if item_proto.type == "fluid" then
            choose_elem_button.elem_value = nil
            local player = game.get_player(flow_product_bar.player_index)
            handle_product_belt_change(player, "")
        end
    end
end

-- Focus the textfield that this product is currently defined_by
function set_appropriate_amount_focus(flow_product_bar, modal_data)
    local defined_by = modal_data.amount_defined_by
    local textfield = flow_product_bar["flow_product_" .. defined_by]["fp_textfield_product_" .. defined_by]
    ui_util.select_all(textfield)
end

-- Updates the product and belt amounts according to the amount_defined_by-state
function update_product_amounts(flow_product_bar, modal_data)
    local lob = modal_data.lanes_or_belts
    local textfield_amount = flow_product_bar["flow_product_amount"]["fp_textfield_product_amount"]
    local textfield_belts = flow_product_bar["flow_product_" .. lob]["fp_textfield_product_" .. lob]

    local defined_by = modal_data.amount_defined_by
    local belt_proto = modal_data.belt_proto
    local multiplier = (lob == "belts") and 1 or 0.5

    if defined_by == "amount" and belt_proto ~= nil then
        local defining_amount = tonumber(textfield_amount.text)
        if defining_amount ~= nil then
            local belts_amount = defining_amount / (belt_proto.throughput * multiplier) / modal_data.timescale
            textfield_belts.text = ui_util.format_number(belts_amount, 4)
        else
            textfield_belts.text = ""
        end

    elseif defined_by == "belts" or defined_by == "lanes" then
        local defining_amount = tonumber(textfield_belts.text)
        if defining_amount ~= nil then
            local amount_amount = defining_amount * (belt_proto.throughput * multiplier) * modal_data.timescale
            textfield_amount.text = ui_util.format_number(amount_amount, 4)
        else
            textfield_amount.text = ""
        end
    end
end


-- Reacts to a picker item button being pressed
function handle_item_picker_product_click(player, identifier)
    local item_proto = identifier_item_map[identifier]
    local modal_data = get_modal_data(player)
    modal_data.selected_item = item_proto

    local flow_product_bar = ui_util.find_modal_dialog(player)["flow_modal_dialog"]["flow_product_bar"]
    local sprite_button_product = flow_product_bar["flow_product_amount"]["sprite-button_product"]
    sprite_button_product.sprite = item_proto.sprite
    sprite_button_product.tooltip = item_proto.localised_name

    adjust_for_item_type(flow_product_bar, modal_data)
    set_appropriate_amount_focus(flow_product_bar, modal_data)
end


-- Updates the product bar with the new selection of belt
function handle_product_belt_change(player, belt_name)
    local belt_proto = global.all_belts.belts[global.all_belts.map[belt_name]]

    local modal_data = get_modal_data(player)
    modal_data.belt_proto = belt_proto

    local lob = modal_data.lanes_or_belts
    local flow_product_bar = ui_util.find_modal_dialog(player)["flow_modal_dialog"]["flow_product_bar"]
    local textfield_product_belts = flow_product_bar["flow_product_" .. lob]["fp_textfield_product_" .. lob]
    textfield_product_belts.enabled = (belt_proto ~= nil)

    if belt_proto == nil then
        modal_data.amount_defined_by = "amount"
        textfield_product_belts.text = ""
    else
        -- Products need to be updated first here so the amount stays the same
        update_product_amounts(flow_product_bar, modal_data)
        modal_data.amount_defined_by = lob
    end

    set_appropriate_amount_focus(flow_product_bar, modal_data)
end

-- Updates the product bar amounts according to the amount_defined_by-state
function handle_product_amount_change(player, defined_by)
    local modal_data = get_modal_data(player)
    modal_data.amount_defined_by = defined_by

    local flow_product_bar = ui_util.find_modal_dialog(player)["flow_modal_dialog"]["flow_product_bar"]
    update_product_amounts(flow_product_bar, modal_data)
end
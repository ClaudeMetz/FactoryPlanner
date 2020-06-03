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
            timescale = subfactory.timescale,
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
            belts_amount = (function(flow_modal_dialog) return
                flow_modal_dialog["flow_product_bar"]["flow_product_belts"]["fp_textfield_product_belts"].text end)
        },
        conditions = {
            [1] = {
                label = {"fp.product_instruction_1"},
                -- Only checking >0 on one of them is enough, as they'll be identical when one is zero
                check = (function(data) return (data.item_sprite == "" or (tonumber(data.amount_amount) == nil
                  and tonumber(data.belts_amount) == nil)) end),
                refocus = (function(flow, data)
                    if data.item_sprite == "" then flow["flow_item_picker"]["table_search_bar"]
                      ["fp_textfield_item_picker_search_bar"].focus()
                    else flow["flow_product_bar"]["flow_product_amount"]["fp_textfield_product_amount"].focus() end
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
    
    local item_sprite, item_tooltip, belt_name
    local item_amount, belt_amount = "", ""
    if product ~= nil then  -- Adjustments if the product is being edited
        modal_data.amount_defined_by = product.required_amount.defined_by
        modal_data.belt_proto = product.required_amount.belt_proto

        item_sprite = product.proto.sprite
        item_tooltip = product.proto.localised_name

        belt_name = (modal_data.belt_proto ~= nil) and modal_data.belt_proto.name or nil

        if modal_data.amount_defined_by == "amount" then
            item_amount = product.required_amount.amount
        else  -- defined_by == "belts"
            belt_amount = product.required_amount.amount
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
    local textfield = flow_product_amount.add{type="textfield", name="fp_textfield_product_amount", text=item_amount}
    ui_util.setup_numeric_textfield(textfield, true, false)
    textfield.style.width = 80

    -- Product amount specification by belt
    local flow_product_belts = flow_product_bar.add{type="flow", name="flow_product_belts", direction="horizontal"}
    flow_product_belts.style.vertical_align = "center"

    local label_belt_amount = flow_product_belts.add{type="label", caption={"fp.amount_by_belts"}}
    label_belt_amount.style.right_margin = 10

    local textfield = flow_product_belts.add{type="textfield", name="fp_textfield_product_belts", text=belt_amount,
      enabled=(modal_data.belt_proto~=nil)}
    ui_util.setup_numeric_textfield(textfield, true, false)
    textfield.style.width = 60

    local label_X = flow_product_belts.add{type="label", caption="X"}
    label_X.style.margin = {0, 3}

    local choose_elem_button = flow_product_belts.add{type="choose-elem-button", elem_type="entity",
      name="fp_choose-elem-button_product_belts", style="fp_sprite-button_choose_elem"}
    choose_elem_button.elem_filters = {{filter="type", type="transport-belt"}}
    choose_elem_button.elem_value = belt_name  -- needs to be set after the filter

    set_appropriate_amount_focus(flow_product_bar, modal_data)
    update_product_amounts(flow_product_bar, modal_data)

    return flow_product_bar
end

-- Focus the textfield that this product is currently defined_by
function set_appropriate_amount_focus(flow_product_bar, modal_data)
    local defined_by = modal_data.amount_defined_by
    flow_product_bar["flow_product_" .. defined_by]["fp_textfield_product_" .. defined_by].focus()
end

-- Updates the product and belt amounts according to the amount_defined_by-state
function update_product_amounts(flow_product_bar, modal_data)
    local textfield_amount = flow_product_bar["flow_product_amount"]["fp_textfield_product_amount"]
    local textfield_belts = flow_product_bar["flow_product_belts"]["fp_textfield_product_belts"]

    local belt_proto = modal_data.belt_proto
    if modal_data.amount_defined_by == "amount" and belt_proto ~= nil then
        local defining_amount = tonumber(textfield_amount.text)
        if defining_amount ~= nil then
            local belts_amount = defining_amount / belt_proto.throughput / modal_data.timescale
            textfield_belts.text = ui_util.format_number(belts_amount, 4)
        else
            textfield_belts.text = ""
        end
    elseif modal_data.amount_defined_by == "belts" then
        local defining_amount = tonumber(textfield_belts.text)
        if defining_amount ~= nil then
            local amount_amount = defining_amount * belt_proto.throughput * modal_data.timescale
            textfield_amount.text = amount_amount
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

    set_appropriate_amount_focus(flow_product_bar, modal_data)
end


-- Updates the product bar with the new selection of belt
function handle_product_belt_change(player, belt_name)
    local belt_proto = global.all_belts.belts[global.all_belts.map[belt_name]]

    local modal_data = get_modal_data(player)
    modal_data.belt_proto = belt_proto

    local flow_product_bar = ui_util.find_modal_dialog(player)["flow_modal_dialog"]["flow_product_bar"]
    local textfield_product_belts = flow_product_bar["flow_product_belts"]["fp_textfield_product_belts"]
    textfield_product_belts.enabled = (belt_proto ~= nil)

    if belt_proto == nil then
        modal_data.amount_defined_by = "amount"
        textfield_product_belts.text = ""
    else
        update_product_amounts(flow_product_bar, modal_data)
        modal_data.amount_defined_by = "belts"
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
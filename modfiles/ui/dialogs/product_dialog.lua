require("ui.elements.item_picker")

-- Handles populating the item picker dialog
function open_product_dialog(flow_modal_dialog, modal_data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local product = modal_data.product

    flow_modal_dialog.parent.caption = (product == nil) and {"fp.add_product"} or {"fp.edit_product"}
    flow_modal_dialog.style.bottom_margin = 8
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
end

-- Handles closing of the item picker dialog
function close_product_dialog(flow_modal_dialog, action, data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local product = ui_state.modal_data.product

    if action == "submit" then
        local req_amount = tonumber(data.required_amount)
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
    end

    calculation.update(player, subfactory, true)
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_product_condition_instructions()
    return {
        data = {
            item_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_product_bar"]["sprite-button_product"].sprite end),
            required_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_product_bar"]["textfield_product_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"fp.product_instruction_1"},
                check = (function(data) return (data.item_sprite == "" or tonumber(data.required_amount) == nil
                  or tonumber(data.required_amount) <= 0) end),
                refocus = (function(flow, data)
                    if data.item_sprite == "" then flow["flow_item_picker"]["table_search_bar"]
                      ["fp_textfield_item_picker_search_bar"].focus()
                    else flow["flow_product_bar"]["textfield_product_amount"].focus() end
                end),
                show_on_edit = true
            }
        }
    }
end


-- Adds a row containing the picked item and it's required_amount
function refresh_product_bar(flow_modal_dialog, product)
    local sprite, required_amount
    if product ~= nil then  -- Adjustments if the product is being edited
        sprite = product.proto.sprite
        required_amount = product.required_amount
        tooltip = product.proto.localised_name
    end
    
    local flow = flow_modal_dialog["flow_product_bar"]
    if flow == nil then
        flow = flow_modal_dialog.add{type="flow", name="flow_product_bar", column_count=4}
        flow.style.bottom_margin = 8
        flow.style.horizontal_spacing = 8
        flow.style.vertical_align = "center"
    end
    flow.clear()
    
    flow.add{type="label", name="label_product", caption={"fp.product"}}
    local button = flow.add{type="sprite-button", name="sprite-button_product", sprite=sprite, tooltip=tooltip,
      style="slot_button"}
    button.style.width = 28
    button.style.height = 28
    button.style.right_margin = 14
    
    flow.add{type="label", name="label_product_amount", caption={"fp.amount"}}
    local textfield = flow.add{type="textfield", name="textfield_product_amount", text=required_amount}
    textfield.style.width = 80
    ui_util.setup_numeric_textfield(textfield, true, false)
    if product ~= nil then textfield.focus() end
    
    return flow
end


-- Reacts to a picker item button being pressed
function handle_item_picker_product_click(player, identifier)
    local item_proto = identifier_item_map[identifier]
    get_modal_data(player).selected_item = item_proto

    local flow_product_bar = player.gui.screen["fp_frame_modal_dialog_product"]["flow_modal_dialog"]["flow_product_bar"]
    flow_product_bar["sprite-button_product"].sprite = item_proto.sprite
    flow_product_bar["sprite-button_product"].tooltip = item_proto.localised_name
    flow_product_bar["textfield_product_amount"].focus()
end
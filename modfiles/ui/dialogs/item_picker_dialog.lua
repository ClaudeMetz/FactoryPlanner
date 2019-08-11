-- Handles populating the item picker dialog
function open_item_picker_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)
    local product = get_ui_state(player).selected_object

    flow_modal_dialog.parent.caption = product == nil and {"label.add_product"} or {"label.edit_product"}
    flow_modal_dialog.style.bottom_margin = 8
    
    local product_bar = refresh_product_bar(flow_modal_dialog, product)
    picker.refresh_search_bar(flow_modal_dialog, "", (product == nil))
    picker.refresh_warning_label(flow_modal_dialog, "")
    picker.refresh_picker_panel(flow_modal_dialog, "item", (product == nil))
    if product ~= nil then product_bar["textfield_product_amount"].focus() end
    
    picker.select_item_group(player, "item", "logistics")
    picker.apply_filter(player, "item", true)
end

-- Handles closing of the item picker dialog
function close_item_picker_dialog(flow_modal_dialog, action, data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local product = ui_state.selected_object

    if action == "submit" then
        local req_amount = tonumber(data.required_amount)
        if product == nil then  -- add product if it doesn't exist (ie. this is not an edit)
            local top_level_item = TopLevelItem.init_by_proto(ui_state.modal_data.selected_item, "Product", 0, req_amount)
            product = Subfactory.add(subfactory, top_level_item)
        else
            product.required_amount = req_amount
        end

    elseif action == "delete" then  -- delete can only be pressed if product ~= nil
        Subfactory.remove(subfactory, product)
    end

    update_calculations(player, subfactory)
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_item_picker_condition_instructions()
    return {
        data = {
            item_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["flow_product_bar"]["sprite-button_product"].sprite end),
            required_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["flow_product_bar"]["textfield_product_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.product_instruction_1"},
                check = (function(data) return (data.item_sprite == "" or data.required_amount == "") end),
                refocus = (function(flow, data)
                    if data.item_sprite == "" then flow["table_search_bar"]["fp_textfield_picker_search_bar"].focus()
                    else flow["flow_product_bar"]["textfield_product_amount"].focus() end
                end),
                show_on_edit = true
            }
        }
    }
end

-- Reacts to a picker item button being pressed
function handle_picker_item_click(player, button)
    local flow_product_bar = player.gui.screen["fp_frame_modal_dialog_item_picker"]["flow_modal_dialog"]["flow_product_bar"]
    local split_name = ui_util.split(button.name, "_")
    local item_proto = global.all_items.types[split_name[6]].items[split_name[7]]

    get_ui_state(player).modal_data.selected_item = item_proto
    flow_product_bar["sprite-button_product"].sprite = button.sprite
    flow_product_bar["sprite-button_product"].tooltip = item_proto.localised_name
    flow_product_bar["textfield_product_amount"].focus()
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
    else
        flow.clear()
    end

    flow.add{type="label", name="label_product", caption={"label.product"}}
    local button = flow.add{type="sprite-button", name="sprite-button_product", sprite=sprite, tooltip=tooltip,
      style="slot_button"}
    button.style.width = 28
    button.style.height = 28
    button.style.right_margin = 14

    flow.add{type="label", name="label_product_amount", caption={"label.amount"}}
    local textfield = flow.add{type="textfield", name="textfield_product_amount", text=required_amount}
    textfield.style.width = 80
    ui_util.setup_numeric_textfield(textfield, true, false)

    return flow
end


-- Returns all items in a format fit for the picker
function get_picker_items()
    -- Combines item and fluid prototypes into an unsorted number-indexed array
    local items = {}
    local types = {"item", "fluid"}
    local all_items = global.all_items
    for _, type in pairs(types) do
        for _, item in pairs(all_items.types[all_items.map[type]].items) do
            table.insert(items, item)
        end
    end
    return items
end


-- Returns the string identifier for the given item
function generate_item_identifier(item)
    local all_items = global.all_items
    local type_id = all_items.map[item.type]
    local item_id = all_items.types[type_id].map[item.name]
    return (type_id .. "_" .. item_id)
end

-- Returns the item described by the identifier
function get_item(identifier)
    local split_ident = ui_util.split(identifier, "_")
    return global.all_items.types[split_ident[1]].items[split_ident[2]]
end

-- Generates the tooltip string for the given item
function generate_item_tooltip(item)
    return item.localised_name
end
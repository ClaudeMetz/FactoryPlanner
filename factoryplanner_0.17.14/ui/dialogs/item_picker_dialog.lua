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
    picker.apply_filter(player, "item", true, nil)
end

-- Handles closing of the item picker dialog
function close_item_picker_dialog(flow_modal_dialog, action, data)
    local player = game.get_player(flow_modal_dialog.player_index)
    local ui_state = get_ui_state(player)
    local subfactory = ui_state.context.subfactory
    local product = ui_state.selected_object

    if action == "submit" then
        if product == nil then  -- add product if it doesn't exist (ie. this is not an edit)
            local split_sprite = ui_util.split(data.item_sprite, "/")
            local item = global.all_items[split_sprite[1]][split_sprite[2]]
            product = Subfactory.add(subfactory, Item.init(item, split_sprite[1], "Product", 0))
        end
        product.required_amount = tonumber(data.required_amount)
        update_calculations(player, subfactory)

    elseif action == "delete" then  -- delete can only be pressed if product ~= nil
        Subfactory.remove(subfactory, product)
        update_calculations(player, subfactory)
    end
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_item_picker_condition_instructions(player)
    return {
        data = {
            item_sprite = (function(flow_modal_dialog) return
              flow_modal_dialog["table_product_bar"]["fp_sprite-button_product"].sprite end),
            required_amount = (function(flow_modal_dialog) return
               flow_modal_dialog["table_product_bar"]["textfield_product_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.product_instruction_1"},
                check = (function(data) return (data.item_sprite == "" or data.required_amount == "") end),
                show_on_edit = true
            },
            [2] = {
                label = {"label.product_instruction_2"},
                check = (function(data) return (data.required_amount ~= "" and (tonumber(data.required_amount) == nil 
                          or tonumber(data.required_amount) <= 0)) end),
                show_on_edit = true
            }
        }
    }
end

-- Reacts to a picker item button being pressed
function handle_picker_item_click(player, button)
    local flow_modal_dialog = player.gui.center["fp_frame_modal_dialog_item_picker"]["flow_modal_dialog"]
    if button.style.name == "fp_button_icon_medium_disabled" then  -- don't accept duplicate products
        --picker.refresh_warning_label(flow_modal_dialog, {"label.error_duplicate_product"})
    else
        --picker.refresh_warning_label(flow_modal_dialog, "")
        
        flow_modal_dialog["table_product_bar"]["fp_sprite-button_product"].sprite = button.sprite
        flow_modal_dialog["table_product_bar"]["textfield_product_amount"].focus()
    end

    --picker.apply_filter(player, "item", false, nil)
end


-- Adds a row containing the picked item and it's required_amount
function refresh_product_bar(flow, product)
    local sprite, required_amount
    if product ~= nil then  -- Adjustments if the product is being edited
        sprite = product.type .. "/" .. product.name
        required_amount = product.required_amount
    end

    local table = flow["table_product_bar"]
    if table == nil then
        table = flow.add{type="flow", name="table_product_bar", column_count=4}
        table.style.bottom_margin = 8
        table.style.horizontal_spacing = 8
        table.style.vertical_align = "center"
    else
        table.clear()
    end

    table.add{type="label", name="label_product", caption={"label.product"}}
    local button = table.add{type="sprite-button", name="fp_sprite-button_product", sprite=sprite, style="slot_button"}
    button.style.width = 28
    button.style.height = 28
    button.style.right_margin = 14

    table.add{type="label", name="label_product_amount", caption={"label.amount"}}
    local textfield = table.add{type="textfield", name="textfield_product_amount", text=required_amount}
    textfield.style.width = 80

    return table
end


-- Returns all items in a format fit for the picker
function get_picker_items()
    -- Combines item and fluid prototypes into an unsorted number-indexed array
    local items = {}
    local types = {"item", "fluid"}
    for _, type in pairs(types) do
        for _, item in pairs(global.all_items[type]) do
            table.insert(items, item)
        end
    end
    return items
end

-- Generates the tooltip string for the given item
function generate_item_tooltip(item, already_exists)
    return item.localised_name
end
-- Returns necessary details to complete the item button for a product
function get_product_specifics(product)
    local localised_name = game[product.type .. "_prototypes"][product.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(product.amount, 4), " / ",
      ui_util.format_number(product.required_amount, 4)}

    local style
    if product.amount == 0 then
        style = "fp_button_icon_large_red"
    elseif product.amount < product.required_amount then
        style = "fp_button_icon_large_yellow"
    elseif product.amount == product.required_amount then
        style = "fp_button_icon_large_green"
    else
        style = "fp_button_icon_large_cyan"
    end

    return {
        number = product.required_amount,
        tooltip = tooltip,
        style = style
    }
end

-- Adds the button to add a product to the table
function append_to_product_table(table)
    local button = table.add{type="sprite-button", name="fp_sprite-button_add_product", sprite="fp_sprite_plus",
      style="fp_sprite_button", tooltip={"tooltip.add_product"}}
    button.style.height = 36
    button.style.width = 36
end


-- Handles populating the modal dialog to add or edit products
function open_product_dialog(flow_modal_dialog)
    create_product_dialog_structure(flow_modal_dialog, {"label.add_product"})
end

-- Handles closing of the product dialog
function close_product_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local product = player_table.selected_object

    if action == "submit" then
        if product == nil then  -- add product if it doesn't exist (ie. this is not an edit)
            product = Subfactory.add(subfactory, Item.init(data.item, "Product"))
        end
        product.required_amount = data.required_amount
        update_calculations(player, subfactory)

    elseif action == "delete" then  -- delete can only be pressed if product ~= nil
        Subfactory.remove(subfactory, product)
        update_calculations(player, subfactory)
    end
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_product_condition_instructions(player)
    local player_table = global.players[player.index]
    return {
        data = {
            item = (function(flow_modal_dialog) return 
              flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value end),
            required_amount = (function(flow_modal_dialog) return 
               tonumber(flow_modal_dialog["table_product"]["textfield_product_amount"].text) end)
        },
        conditions = {
            [1] = {
                label = {"label.product_instruction_1"},
                check = (function(data) return (data.item == nil or data.required_amount == "") end),
                show_on_edit = true
            },
            [2] = {
                label = {"label.product_instruction_2"},
                check = (function(data) return (player_table.selected_object == nil and 
                          Subfactory.get_by_name(player_table.context.subfactory, "Product", data.item.name)) end),
                show_on_edit = false
            },
            [3] = {
                label = {"label.product_instruction_3"},
                check = (function(data) return (data.item ~= nil and data.item.type == "virtual") end),
                show_on_edit = false
            },
            [4] = {
                label = {"label.product_instruction_4"},
                check = (function(data) return (data.required_amount ~= "" and (tonumber(data.required_amount) == nil 
                          or tonumber(data.required_amount) <= 0)) end),
                show_on_edit = true
            }
        }
    }
end

-- Fills out the modal dialog to add or edit a product
function create_product_dialog_structure(flow_modal_dialog, title)
    flow_modal_dialog.parent.caption = title

    local table_product = flow_modal_dialog.add{type="table", name="table_product", column_count=2}
    table_product.style.bottom_padding = 6
    -- Product
    table_product.add{type="label", name="label_product", caption={"label.product"}}
    local button_product = table_product.add{type="choose-elem-button", name="choose-elem-button_product", 
      elem_type="signal"}

    -- Amount
    table_product.add{type="label", name="label_product_amount", caption={"", {"label.amount"}, "    "}}
    local textfield_product_amount = table_product.add{type="textfield", name="textfield_product_amount"}
    textfield_product_amount.style.width = 80
    textfield_product_amount.focus()

    -- Adjustments if the product is being edited
    local product = global.players[flow_modal_dialog.player_index].selected_object
    if product ~= nil then
        button_product.elem_value = {type=product.type, name=product.name}
        button_product.locked = true
        --button_product.enabled = false
        textfield_product_amount.text = product.required_amount
    end
end


-- Opens modal dialogs of clicked element or shifts it's position left or right
function handle_product_element_click(player, product_id, click, direction)
    local player_table = global.players[player.index]
    local subfactory = player_table.context.subfactory
    local product = Subfactory.get(subfactory, "Product", product_id)

    -- Shift product in the given direction
    if direction ~= nil then
        Subfactory.shift(subfactory, product, direction)

    else  -- Open modal dialogs
        if click == "left" then
            if player_table.context.floor.level == 1 then
                enter_modal_dialog(player, {type="recipe_picker", object=product, preserve=true})
            else
                queue_hint_message(player, {"label.error_product_wrong_floor"})
            end
        elseif click == "right" then
            enter_modal_dialog(player, {type="product", object=product, submit=true, delete=true})
        end
    end
    
    refresh_item_table(player, "Product")
end
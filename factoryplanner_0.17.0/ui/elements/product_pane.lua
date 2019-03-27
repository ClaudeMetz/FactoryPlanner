-- Returns necessary details to complete the item button for a product
function get_product_specifics(product)
    local localised_name = game[product.item_type .. "_prototypes"][product.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(product.amount_produced, 4), " / ",
      ui_util.format_number(product.amount_required, 4)}

    local style
    if product.amount_produced == 0 then
        style = "fp_button_icon_large_red"
    elseif product.amount_produced < product.amount_required then
        style = "fp_button_icon_large_yellow"
    elseif product.amount_produced == product.amount_required then
        style = "fp_button_icon_large_green"
    else
        style = "fp_button_icon_large_cyan"
    end

    return {
        number = product.amount_required,
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
function open_product_dialog(flow_modal_dialog, args)
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]
    if args.edit then 
        player_table.current_activity = "editing_product"
        player_table.selected_product_name = Subfactory.get(player, player_table.selected_subfactory_id, 
          "Product", args.product_id).name
    end
    create_product_dialog_structure(flow_modal_dialog, {"label.add_product"})
end

-- Handles closing of the product dialog
function close_product_dialog(flow_modal_dialog, action, data)
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]
    local subfactory_id = player_table.selected_subfactory_id
    local product = Subfactory.find_by_name(player, subfactory_id, "Product", player_table.selected_product_name)

    if action == "submit" then
        if player_table.current_activity == "editing_product" then
            Product.set_amount_required(player, subfactory_id, product.id, tonumber(data.amount_required))
        else
            Subfactory.add(player, subfactory_id, Product.init(data.item, tonumber(data.amount_required)))
        end

    elseif action == "delete" then
        Subfactory.delete(player, subfactory_id, "Product", product.id)
    end

    player_table.selected_product_name = nil
    update_calculations(player, subfactory_id)
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_product_condition_instructions(player)
    local player_table = global.players[player.index]
    return {
        data = {
            item = (function(flow_modal_dialog) return 
              flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value end),
            amount_required = (function(flow_modal_dialog) return 
              flow_modal_dialog["table_product"]["textfield_product_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.product_instruction_1"},
                check = (function(data) return (data.item == nil or data.amount_required == "") end),
                show_on_edit = true
            },
            [2] = {
                label = {"label.product_instruction_2"},
                check = (function(data) return (player_table.selected_product_name == nil and 
                          Subfactory.product_exists(player, player_table.selected_subfactory_id, data.item)) end),
                show_on_edit = false
            },
            [3] = {
                label = {"label.product_instruction_3"},
                check = (function(data) return (data.item ~= nil and data.item.type == "virtual") end),
                show_on_edit = false
            },
            [4] = {
                label = {"label.product_instruction_4"},
                check = (function(data) return (data.amount_required ~= "" and (tonumber(data.amount_required) == nil or
                          tonumber(data.amount_required) <= 0)) end),
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
    local player = game.players[flow_modal_dialog.player_index]
    local player_table = global.players[player.index]

    if player_table.selected_product_name ~= nil then
        local product = Subfactory.find_by_name(player, player_table.selected_subfactory_id, "Product",
          player_table.selected_product_name)
        button_product.elem_value = {type=product.item_type, name=product.name}
        button_product.locked = true
        --button_product.enabled = false
        textfield_product_amount.text = product.amount_required
    end
end


-- Opens modal dialogs of clicked element or shifts it's position left or right
function handle_product_element_click(player, product_id, click, direction)
    local player_table = global.players[player.index]
    local subfactory_id = player_table.selected_subfactory_id

    -- Shift product in the given direction
    if direction ~= nil then
        Subfactory.shift(player, subfactory_id, "Product", product_id, direction)

    -- Open modal dialogs
    else
        if click == "left" then
            local floor = Subfactory.get(player, subfactory_id, "Floor", Subfactory.get_selected_floor_id(player, subfactory_id))
            if floor.level == 1 then
                local product_name = Product.get_name(player, subfactory_id, product_id)
                enter_modal_dialog(player, "recipe_picker", {preserve=true}, {product_name=product_name})
            else
                queue_hint_message(player, {"label.error_product_wrong_floor"})
            end
        elseif click == "right" then
            enter_modal_dialog(player, "product", {submit=true, delete=true}, {edit=true, product_id=product_id})
        end
    end
    
    refresh_item_table(player, "Product")
end
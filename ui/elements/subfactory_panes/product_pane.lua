require("ui.elements.subfactory_panes.recipe_dialog")

-- Constructs the table containing all product buttons
function refresh_product_pane(player)
    local flow = player.gui.center["fp_main_dialog"]["table_subfactory_pane"]["flow_products"]
    if flow["table_products"] == nil then
        flow.add{type="table", name="table_products", column_count = 6}
        flow["table_products"].style.left_padding = 10
        flow["table_products"].style.horizontal_spacing = 10
    else
        flow["table_products"].clear()
    end

    local subfactory_id = global["selected_subfactory_id"]
    if Subfactory.get_count(subfactory_id, "Product") ~= 0 then
        for _, id in ipairs(Subfactory.get_in_order(subfactory_id, "Product")) do
            local product = Subfactory.get(subfactory_id, "Product", id)

            local button = flow["table_products"].add{type="sprite-button", name="fp_sprite-button_product_" .. id, 
                sprite=product.item_type .. "/" .. product.name, number=product.amount_required}

            local localised_name = game[product.item_type .. "_prototypes"][product.name].localised_name
            button.tooltip = {"", localised_name, "\n", product.amount_produced, " / ", product.amount_required}

            if product.amount_produced == 0 then
                button.style = "fp_button_icon_red"
            elseif product.amount_produced < product.amount_required then
                button.style = "fp_button_icon_yellow"
            elseif product.amount_produced == product.amount_required then
                button.style = "fp_button_icon_green"
            else
                button.style = "fp_button_icon_cyan"
            end
        end
    end

    local button = flow["table_products"].add{type="button", name="fp_sprite-button_add_product", caption="+"}
    button.style.height = 36
    button.style.width = 36
    button.style.top_padding = 0
    button.style.font = "fp-button-large"
end


-- Handles populating the modal dialog to add or edit products
function open_product_dialog(flow_modal_dialog, args)
    if args.edit then 
        global["current_activity"] = "editing_product"
        global["selected_product_id"] = args.product_id
    end
    create_product_dialog_structure(flow_modal_dialog, {"label.add_product"})
end

-- Handles closing of the product dialog
function close_product_dialog(flow_modal_dialog, action, data)
    local subfactory_id = global["selected_subfactory_id"]
    local product_id = global["selected_product_id"]

    if action == "submit" then
        if global["current_activity"] == "editing_product" then
            Product.set_amount_required(subfactory_id, product_id, data.amount_required)
        else
            local product = Product.init(data.item, data.amount_required)
            Subfactory.add(subfactory_id, product)
        end

    elseif action == "delete" then
        Subfactory.delete(subfactory_id, "Product", product_id)
    end

    global["selected_product_id"] = 0
end


-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_product_condition_instructions()
    return {
        data = {
            item = (function(flow_modal_dialog) return flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value end),
            amount_required = (function(flow_modal_dialog) return flow_modal_dialog["table_product"]["textfield_product_amount"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.product_instruction_1"},
                check = (function(data) return (data.item == nil or data.amount_required == "") end),
                show_on_edit = false
            },
            [2] = {
                label = {"label.product_instruction_2"},
                check = (function(data) return (global["selected_product_id"] == 0 and 
                          Subfactory.product_exists(global["selected_subfactory_id"], data.item)) end),
                show_on_edit = false
            },
            [3] = {
                label = {"label.product_instruction_3"},
                check = (function(data) return (data.item ~= nil and data.item.type == "virtual") end),
                show_on_edit = false
            },
            [4] = {
                label = {"label.product_instruction_4"},
                check = (function(data) return (data.amount_required ~= "" and (data.amount_required:match("[^%d]") or 
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
    table_product.style.bottom_padding = 8
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
    local product_id = global["selected_product_id"]
    if product_id ~= 0 then
        local product = Subfactory.get(global["selected_subfactory_id"], "Product", product_id)
        button_product.elem_value = {type=product.item_type, name=product.name}
        textfield_product_amount.text = product.amount_required
        button_product.locked = true
    end
end


-- Opens modal dialogs of clicked element or shifts it's position left or right
function handle_product_element_click(player, product_id, click, direction)
    -- Shift product in the given direction
    if direction ~= nil then
        Subfactory.shift(global["selected_subfactory_id"], "Product", product_id, direction)

    -- Open modal dialogs
    else
        if click == "left" then
            open_recipe_dialog(player, product_id)
        elseif click == "right" then
            enter_modal_dialog(player, "product", true, true, {edit=true, product_id=product_id})
        end
    end
    refresh_product_pane(player)
end
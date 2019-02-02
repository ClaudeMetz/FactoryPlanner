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

    local products = get_products(global["selected_subfactory_id"])
    if #products ~= 0 then
        for id, product in ipairs(products) do
            local button = flow["table_products"].add{type="sprite-button", name="fp_sprite-button_product_" .. id, 
                sprite="item/" .. product.name, number=product.amount_required}

            button.tooltip = {"", game.item_prototypes[product.name].localised_name, "\n",
              product.amount_produced, " / ", product.amount_required}

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
    if args.edit then global["selected_product_id"] = args.product_id end
    create_product_dialog_structure(flow_modal_dialog, {"label.add_product"})
end

-- Handles submission of the product dialog
function submit_product_dialog(flow_modal_dialog, data)
    selected_product_id = global["selected_product_id"]
    if selected_product_id ~= 0 then
        set_product_amount_required(global["selected_subfactory_id"], selected_product_id, data.amount_required)
        global["selected_product_id"] = 0
    else
        add_product(global["selected_subfactory_id"], data.product_name, data.amount_required)
    end
end

-- Handles the product deletion process
function delete_product_dialog()
    delete_product(global["selected_subfactory_id"], global["selected_product_id"])
    global["selected_product_id"] = 0
end

-- Resets the selected id if the modal dialog is cancelled
function cleanup_product_dialog()
    global["selected_product_id"] = 0
end

-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_product_data(flow_modal_dialog)
    local product_name = flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value
    local amount = flow_modal_dialog["table_product"]["textfield_product_amount"].text
    local instruction_1 = flow_modal_dialog["table_conditions"]["label_product_instruction_1"]
    local instruction_2 = flow_modal_dialog["table_conditions"]["label_product_instruction_2"]
    local instruction_3 = flow_modal_dialog["table_conditions"]["label_product_instruction_3"]

    -- Resets all error indicators
    set_label_color(instruction_1, "white")
    set_label_color(instruction_2, "white")
    set_label_color(instruction_3, "white")
    local error_present = false

    if product_name == nil or amount == "" then
        set_label_color(instruction_1, "red")
        error_present = true
    end

    if global["selected_product_id"] == 0 and product_exists(global["selected_subfactory_id"], product_name) then
        set_label_color(instruction_2, "red")
        error_present = true
    end

    -- Matches everything that is not numeric
    if amount ~= "" and (amount:match("[^%d]") or tonumber(amount) <= 0) then
        set_label_color(instruction_3, "red")
        error_present = true
    end

    if error_present then
        return nil
    else
        return {product_name=product_name, amount_required=tonumber(amount)}
    end
end

-- Fills out the modal dialog to add or edit a product
function create_product_dialog_structure(flow_modal_dialog, title)
    flow_modal_dialog.parent.caption = title

    local product_id = global["selected_product_id"]
    local product = get_product(global["selected_subfactory_id"], product_id)

    -- Conditions
    local table_conditions = flow_modal_dialog.add{type="table", name="table_conditions", column_count=1}
    table_conditions.add{type="label", name="label_product_instruction_1", caption={"label.product_instruction_1"}}
    table_conditions.add{type="label", name="label_product_instruction_2", caption={"label.product_instruction_2"}}
    table_conditions.add{type="label", name="label_product_instruction_3", caption={"label.product_instruction_3"}}
    table_conditions.style.bottom_padding = 6

    local table_product = flow_modal_dialog.add{type="table", name="table_product", column_count=2}
    table_product.style.bottom_padding = 8
    -- Product
    table_product.add{type="label", name="label_product", caption={"label.product"}}
    table_product.add{type="choose-elem-button", name="choose-elem-button_product", elem_type="item", item=product.name}

    -- Amount
    table_product.add{type="label", name="label_product_amount", caption={"", {"label.amount"}, "    "}}
    local textfield_product = table_product.add{type="textfield", name="textfield_product_amount", text=product.amount_required}
    textfield_product.style.width = 80
    textfield_product.focus()

    -- Adjustments if the product is being edited
    if product_id ~= 0 then
        table_conditions["label_product_instruction_2"].style.visible = false
        table_product["choose-elem-button_product"].locked = true
    end
end
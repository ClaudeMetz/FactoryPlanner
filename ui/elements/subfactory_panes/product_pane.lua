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

    local subfactory = global["factory"]:get_selected_subfactory()
    if subfactory:get_count("product") ~= 0 then
        for _, id in ipairs(subfactory:get_in_order("product")) do
            local product = subfactory:get("product", id)

            local button = flow["table_products"].add{type="sprite-button", name="fp_sprite-button_product_" .. id, 
                sprite="item/" .. product:get_name(), number=product:get_amount_required()}
            button.tooltip = {"", game.item_prototypes[product:get_name()].localised_name, "\n",
              product:get_amount_produced(), " / ", product:get_amount_required()}

            if product:get_amount_produced() == 0 then
                button.style = "fp_button_icon_red"
            elseif product:get_amount_produced() < product:get_amount_required() then
                button.style = "fp_button_icon_yellow"
            elseif product:get_amount_produced() == product:get_amount_required() then
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
    local subfactory = global["factory"]:get_selected_subfactory()
    if global["selected_product_id"] ~= 0 then
        subfactory:get("product", global["selected_product_id"]):set_amount_required(data.amount_required)
        global["selected_product_id"] = 0
    else
        local product = Product(data.product_name, data.amount_required)
        subfactory:add("product", product)
    end
end

-- Handles the product deletion process
function delete_product_dialog()
    global["factory"]:get_selected_subfactory():delete("product", global["selected_product_id"])
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
    
    if global["selected_product_id"] == 0 and global["factory"]:get_selected_subfactory():product_exists(product_name) then
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
    local button_product = table_product.add{type="choose-elem-button", name="choose-elem-button_product", 
      elem_type="item"}

    -- Amount
    table_product.add{type="label", name="label_product_amount", caption={"", {"label.amount"}, "    "}}
    local textfield_product_amount = table_product.add{type="textfield", name="textfield_product_amount"}
    textfield_product_amount.style.width = 80
    textfield_product_amount.focus()

    -- Adjustments if the product is being edited
    local product_id = global["selected_product_id"]
    if product_id ~= 0 then
        local product = global["factory"]:get_selected_subfactory():get("product", product_id)
        button_product.elem_value = product:get_name()
        textfield_product_amount.text = product:get_amount_required()

        table_conditions["label_product_instruction_2"].style.visible = false
        button_product.locked = true
    end
end


-- Opens modal dialogs of clicked element or shifts it's position left or right
function handle_product_element_click(player, product_id, click, direction)
    -- Shift product in the given direction
    if direction ~= nil then
        global["factory"]:get_selected_subfactory():shift("product", product_id, direction)

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
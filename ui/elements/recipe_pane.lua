-- Creates the recipe pane that includes the products, byproducts and ingredients
function add_recipe_pane_to(main_dialog, player)
    main_dialog.add{type="table", name="table_recipe_pane", direction="horizontal", column_count = 4}
    refresh_recipe_pane(player)
end


-- Refreshes the recipe pane by reloading the data
function refresh_recipe_pane(player)
    -- Structure provisional for now, info cell might get axed if it turns out it's not needed
    local table_recipe =  player.gui.center["main_dialog"]["table_recipe_pane"]
    -- Cuts function short if the recipe pane hasn't been initialized yet
    if not table_recipe then return end

    table_recipe.style.horizontally_stretchable = true
    table_recipe.draw_vertical_lines = true
    table_recipe.clear()

    local selected_subfactory_id = global["selected_subfactory_id"]
    -- selected_subfactory_id is always 0 when there are no subfactories
    if selected_subfactory_id ~= 0 then
        -- Info cell
        local flow_info = create_recipe_pane_cell(table_recipe, "info")
        refresh_info_pane(player)
        
        -- Ingredients cell
        create_recipe_pane_cell(table_recipe, "ingredients")

        -- Products cell
        local flow_recipe = create_recipe_pane_cell(table_recipe, "products")
        local products = get_products(selected_subfactory_id)
        create_product_buttons(flow_recipe, products)

        -- Byproducts cell
        create_recipe_pane_cell(table_recipe, "byproducts")

    end
end


-- Constructs the basic structure of a recipe_pane-cell
function create_recipe_pane_cell(table, kind)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. kind, direction="vertical"}
    flow.style.width = width
    local label_title = flow.add{type="label", name="label_" .. kind .. "_title", caption={"", "  ", {"label." ..kind}}}
    label_title.style.font = "fp-button-standard"

    return flow
end


-- Constructs the info pane including timescale settings
function refresh_info_pane(player)
    local flow = player.gui.center["main_dialog"]["table_recipe_pane"]["flow_info"]
    if not flow["flow_info_list"] then
        flow.add{type="flow", name="flow_info_list", direction="vertical"}
    else
        flow["flow_info_list"].clear()
    end

    local timescale = get_subfactory_timescale(global["selected_subfactory_id"])
    local unit = determine_unit(timescale)
    local table_timescale = flow["flow_info_list"].add{type="table", name="table_timescale_buttons", column_count=4}
    local label_timescale_title = table_timescale.add{type="label", name="label_timescale_title",
      caption={"", " ", {"label.timescale"}, ": "}}
    label_timescale_title.style.top_padding = 1
    label_timescale_title.style.font = "fp-label-large"

    if global["currently_changing_timescale"] then
        table_timescale.add{type="button", name="button_timescale_1", caption="1s", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="button_timescale_60", caption="1m", style="fp_button_speed_selection"}
        table_timescale.add{type="button", name="button_timescale_3600", caption="1h", style="fp_button_speed_selection"}
    else            
        -- As unit is limited to presets, timescale will always be displayed as 1
        local label_timescale = table_timescale.add{type="label", name="label_timescale", caption="1" .. unit .. "   "}
        label_timescale.style.top_padding = 1
        label_timescale.style.font = "default-bold"
        table_timescale.add{type="button", name="button_change_timescale", caption={"button-text.change"},
          style="fp_button_speed_selection"}
    end

    local table_power_usage = flow["flow_info_list"].add{type="table", name="table_power_usage", column_count=2}
    table_power_usage.add{type="label", name="label_power_usage_title", caption={"", " ",  {"label.power_usage"}, ": "}}
    table_power_usage["label_power_usage_title"].style.font = "fp-label-large"
    local power_usage = "14.7 MW"  -- Placeholder until a later implementation
    table_power_usage.add{type="label", name="label_power_usage", caption=power_usage .. "/" .. unit}
    table_power_usage["label_power_usage"].style.font = "default-bold"
end


-- Handles the timescale changing process
function change_subfactory_timescale(player, timescale)
    set_subfactory_timescale(global["selected_subfactory_id"], timescale)
    global["currently_changing_timescale"] = false
    refresh_info_pane(player)
end


-- Constructs the table containing all product buttons
function create_product_buttons(flow, items)
    local table = flow.add{type="table", name="table_products", column_count = 6}
    table.style.left_padding = 10
    table.style.horizontal_spacing = 10

    if #items ~= 0 then
        for id, product in ipairs(items) do
            local button = table.add{type="sprite-button", name="sprite-button_product_" .. id, 
                sprite="item/" .. product.name, number=product.amount_required}

            button.tooltip = {"", game.item_prototypes[product.name].localised_name, "\n",
              product.amount_produced," / ", product.amount_required}

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

    local button = table.add{type="button", name="sprite-button_add_product", caption="+"}
    button.style.height = 36
    button.style.width = 36
    button.style.top_padding = 0
    button.style.font = "fp-button-large"
end


-- Handles populating the modal dialog to add or edit products
function open_product_dialog(flow_modal_dialog, args)
    if args.edit then
        global["currently_editing_product_id"] = args.product_id
        create_product_dialog_structure(flow_modal_dialog, {"label.edit_product"}, args.product_id)
    else
        create_product_dialog_structure(flow_modal_dialog, {"label.add_product"}, nil)
    end
end

-- Handles submission of the product dialog
function submit_product_dialog(flow_modal_dialog)
    local data = check_product_data(flow_modal_dialog)
    if data ~= nil then  -- meaning correct data has been entered
        current_product_id = global["currently_editing_product_id"]
        if current_product_id ~= nil then
            set_product_amount_required(global["selected_subfactory_id"], current_product_id, data.amount_required)
            global["currently_editing_product_id"] = nil
        else
            add_product(global["selected_subfactory_id"], data.product_name, data.amount_required)
        end
        -- This closes the modal dialog, only returned when correct data has been entered
        return true
    else
        return false
    end
end

-- Checks the entered data for errors and returns it if it's all correct, else returns nil
function check_product_data(flow_modal_dialog)
    local product = flow_modal_dialog["table_product"]["choose-elem-button_product"].elem_value
    local amount = flow_modal_dialog["table_product"]["textfield_product_amount"].text
    local label_product = flow_modal_dialog["table_product"]["label_product"]
    local label_amount = flow_modal_dialog["table_product"]["label_product_amount"]

    -- Resets all error indicators
    set_label_color(label_product, "white")
    set_label_color(label_amount, "white")
    local error_present = false

    if product == nil then
        set_label_color(label_product, "red")
        error_present = true
    end

    -- Matches everything that is not numeric
    if amount == "" or amount:match("[^%d]") or tonumber(amount) <= 0 then
        set_label_color(label_amount, "red")
        error_present = true
    end

    if error_present then
        return nil
    else
        return {product_name=product, amount_required=tonumber(amount)}
    end
end

-- Fills out the modal dialog to add a product
function create_product_dialog_structure(flow_modal_dialog, title, product_id)
    local product
    if product_id ~= nil then
        product = get_product(global["selected_subfactory_id"], product_id)
    else
        product = {name=nil, amount_required=""}
    end

    flow_modal_dialog.parent.caption = title

    -- Delete
    if product_id ~= nil then
        local button_delete = flow_modal_dialog.add{type="button", name="button_delete_product",
        caption={"button-text.delete"}, style="fp_button_action"}
        set_label_color(button_delete, "red")
    end

    local table_product = flow_modal_dialog.add{type="table", name="table_product", column_count=2}
    table_product.style.top_padding = 5
    table_product.style.bottom_padding = 8
        -- Product
    table_product.add{type="label", name="label_product", caption={"label.product"}}
    table_product.add{type="choose-elem-button", name="choose-elem-button_product", elem_type="item", item=product.name}
    if product_id ~= nil then table_product["choose-elem-button_product"].locked = true end

    -- Amount
    table_product.add{type="label", name="label_product_amount", caption={"", {"label.amount"}, "    "}}
    local textfield_product = table_product.add{type="textfield", name="textfield_product_amount", text=product.amount_required}
    textfield_product.style.width = 80
    textfield_product.focus()
end

-- Handles the product deletion process
-- (a bit of misuse of exit_modal_dialog(), but it fits the need)
function handle_product_deletion(player)
    delete_product(global["selected_subfactory_id"], global["currently_editing_product_id"])
    global["currently_editing_product_id"] = nil
    exit_modal_dialog(player, false)
    refresh_main_dialog(player)
end
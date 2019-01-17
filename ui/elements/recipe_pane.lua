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
        --create_item_buttons(flow_recipe, products, "products")

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
    local power_usage = 14.7  -- Placeholder until a later implementation
    table_power_usage.add{type="label", name="label_power_usage", caption=power_usage .. " MW/" .. unit}
    table_power_usage["label_power_usage"].style.font = "default-bold"
end


-- Handles the timescale changing process
function change_subfactory_timescale(player, timescale)
    set_subfactory_timescale(global["selected_subfactory_id"], timescale)
    global["currently_changing_timescale"] = false
    refresh_info_pane(player)
end





--[[ -- Saved for later implementation reference
-- Constructs the table containing all item buttons of the given kind
-- (Everything is called an item, even fluids, they get treated the same)
function create_item_buttons(flow, items, kind)
    if #items ~= 0 then
        local table = flow.add{type="table", name="table_" .. kind, column_count = 5}
        table.style.left_padding = 10
        table.style.horizontal_spacing = 16
        if kind == "products" then
            local button
            for id, product in ipairs(items) do
                local display_number = product.amount_required - product.amount_produced
                button = table.add{type="sprite-button", name="sprite-button_product_" .. id, 
                  sprite="item/" .. product.name, number = display_number}
            end
            button.style = "trans-image-button-style"
        end
    end
end ]]
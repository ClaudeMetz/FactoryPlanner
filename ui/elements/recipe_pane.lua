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
        create_recipe_pane_cell(table_recipe, "information", false)

        -- Ingredients cell
        create_recipe_pane_cell(table_recipe, "ingredients", true)

        -- Products cell
        local flow_recipe = create_recipe_pane_cell(table_recipe, "products", true)
        local products = get_products(selected_subfactory_id)
        --create_item_buttons(flow_recipe, products, "products")

        -- Byproducts cell
        create_recipe_pane_cell(table_recipe, "byproducts", true)

        table_recipe.add{type="label", name="label_information", caption=" Power usage: 14.7 MW"}
    end
end

-- Constructs the basic structure of a recipe_pane-cell
function create_recipe_pane_cell(table, kind, add_scrollpane)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. kind, direction="vertical"}
    flow.style.width = width
    local capitalized_title = "   " .. (kind:gsub("^%l", string.upper))
    local label_title = flow.add{type="label", name="label_" .. kind .. "_title", caption = capitalized_title}
    label_title.style.font = "fp-button-standard"

    return flow
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
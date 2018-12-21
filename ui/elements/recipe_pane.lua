-- Creates the recipe pane that includes the products, byproducts and ingredients
function add_recipe_pane_to(main_dialog, player)
    main_dialog.add{type="table", name="table_recipe_pane", direction="horizontal", column_count = 4}
    refresh_recipe_pane(player)
end


-- Refreshes the recipe pane by reloading the data
function refresh_recipe_pane(player)
    -- Structure provisional for now, info cell might get axed if it turns out it's not needed
    local table_recipe =  player.gui.center["main_dialog"]["table_recipe_pane"]
    table_recipe.style.horizontally_stretchable = true
    table_recipe.draw_vertical_lines = true
    table_recipe.clear()

    -- selected_subfactory_id is always 0 when there are no subfactories
    if global["selected_subfactory_id"] ~= 0 then
        -- Info cell
        create_basic_recipe_pane_cell(table_recipe, "information", false)

        -- Products cell
        create_basic_recipe_pane_cell(table_recipe, "products", true)
        
        -- Ingredients cell
        create_basic_recipe_pane_cell(table_recipe, "ingredients", true)

        -- Byproducts cell
        create_basic_recipe_pane_cell(table_recipe, "byproducts", true)


        table_recipe.add{type="label", name="label_information", caption=" Power usage: 14.7 MW"}
    end
end

-- Constructs the basic structure of a recipe_pane-cell
function create_basic_recipe_pane_cell(table, kind, add_scrollpane)
    local width = global["main_dialog_dimensions"].width / 4 - 6
    local flow = table.add{type="flow", name="flow_" .. kind, direction="vertical"}
    flow.style.width = width
    local capitalized_title = "   " .. (kind:gsub("^%l", string.upper))
    local label_title = flow.add{type="label", name="label_" .. kind .. "_title", caption = capitalized_title}
    label_title.style.font = "fp-button-standard"

end
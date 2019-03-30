-- Returns necessary details to complete the item button for an ingredient
function get_ingredient_specifics(ingredient)
    local localised_name = game[ingredient.item_type .. "_prototypes"][ingredient.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(ingredient.amount, 4)}

    return {
        number = ingredient.amount,
        tooltip = tooltip,
        style = "fp_button_icon_large_blank"
    }
end

-- Shifts clicked element's position left or right
function handle_ingredient_element_click(player, ingredient_id, click, direction)
    if direction ~= nil then
        local subfactory = global.players[player.index].context.subfactory
        local ingredient = Subfactory.get(subfactory, "Ingredient", ingredient_id)
        Subfactory.shift(subfactory, ingredient, direction)
        refresh_item_table(player, "Ingredient")
    end
end
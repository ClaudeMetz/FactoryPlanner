-- Returns necessary details to complete the item button for an ingredient
function get_ingredient_specifics(ingredient)
    local localised_name = game[ingredient.item_type .. "_prototypes"][ingredient.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(ingredient.amount_required, 4)}

    return {
        number = ingredient.amount_required,
        tooltip = tooltip,
        style = "fp_button_icon_large_blank"
    }
end

-- Shifts clicked element's position left or right
function handle_ingredient_element_click(player, ingredient_id, click, direction)
    if direction ~= nil then
        Subfactory.shift(player, global.players[player.index].selected_subfactory_id, "Ingredient", ingredient_id, direction)
        refresh_item_table(player, "Ingredient")
    end
end
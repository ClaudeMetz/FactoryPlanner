-- Returns necessary details to complete the item button for a byproduct
function get_byproduct_specifics(byproduct)
    local localised_name = game[byproduct.item_type .. "_prototypes"][byproduct.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(byproduct.amount_produced, 4)}

    return {
        number = byproduct.amount_produced,
        tooltip = tooltip,
        style = "fp_button_icon_large_red"
    }
end


-- Opens recipe dialog of clicked element or shifts it's position left or right
function handle_byproduct_element_click(player, byproduct_id, click, direction)
    -- Shift byproduct in the given direction
    if direction ~= nil then
        Subfactory.shift(global["selected_subfactory_id"], "Byproduct", byproduct_id, direction)

    -- Open recipe dialog ?
    -- Dealing with byproducts will come at a later stage
    elseif click == "left" then
        --open_recipe_dialog(player, byproduct_id)
    end

    refresh_item_table(player, "Byproduct")
end
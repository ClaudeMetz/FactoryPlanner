-- Returns necessary details to complete the item button for a byproduct
function get_byproduct_specifics(byproduct)
    local localised_name = game[byproduct.item_type .. "_prototypes"][byproduct.name].localised_name
    local tooltip = {"", localised_name, "\n", ui_util.format_number(byproduct.amount, 4)}

    return {
        number = byproduct.amount,
        tooltip = tooltip,
        style = "fp_button_icon_large_red"
    }
end


-- Opens recipe dialog of clicked element or shifts it's position left or right
function handle_byproduct_element_click(player, byproduct_id, click, direction)
    local subfactory = global.players[player.index].context.subfactory
    
    -- Shift byproduct in the given direction
    if direction ~= nil then
        local byproduct = Subfactory.get(subfactory, "Byproduct", byproduct_id)
        Subfactory.shift(subfactory, byproduct, direction)

    -- Open recipe dialog? Dealing with byproducts will come at a later stage
    elseif click == "left" then
        local floor = global.players[player.index].context.floor
        if floor.level == 1 then
            -- open recipe picker for byproducts
        else
            queue_hint_message(player, {"label.error_byproduct_wrong_floor"})
        end
    end

    refresh_item_table(player, "Byproduct")
end
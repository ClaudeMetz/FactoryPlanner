migration_0_18_20 = {}

function migration_0_18_20.global()
end

function migration_0_18_20.player_table(player, player_table)
end

function migration_0_18_20.subfactory(player, subfactory)
    local types = {"Ingredient", "Product", "Byproduct"}
    for _, type in pairs(types) do
        for _, item in pairs(Subfactory.get_in_order(subfactory, type)) do
            local req_amount = {
                defined_by = "amount",
                amount = item.required_amount
            }
            item.required_amount = req_amount
        end
    end
end
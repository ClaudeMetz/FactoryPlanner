migration_0_18_29 = {}

function migration_0_18_29.global()
end

function migration_0_18_29.player_table(player, player_table)
end

function migration_0_18_29.subfactory(player, subfactory)
    if get_settings(player).belts_or_lanes == "lanes" then
        for _, product in pairs(Subfactory.get_in_order(subfactory, "Product")) do
            if product.required_amount.defined_by == "belts" then
                product.required_amount.defined_by = "lanes"
                product.required_amount.amount = product.required_amount.amount * 2
            end
        end
    end
end
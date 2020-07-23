local migration = {}

function migration.subfactory(subfactory)
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

return migration
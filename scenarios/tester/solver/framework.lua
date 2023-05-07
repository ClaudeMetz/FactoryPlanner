local framework = {}

function framework.check_top_level_product(subfactory, name, expected_amount)
    local product = Subfactory.get_by_name(subfactory, "Product", name)  -- assume this exists
    local actual_amount = product.amount
    if actual_amount ~= expected_amount then
        return "Expected " .. expected_amount .. " of " .. name .. ", got " .. actual_amount
    else
        return "pass"
    end
end

return framework

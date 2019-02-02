-- Fixing Py Raw Ores duplicate item_group ordering for him
-- If any other mods have this issue, they won't be fixed automatically
if mods["pyrawores"] then
    data.raw["item-group"]["py-rawores"].order = "x"
end

-- Trying to fix missing link in space science production, might interfere with other mods in this form
data:extend({{
        type = "recipe",
        name = "space-science-pack",
        enabled = false,
        hidden = true,
        energy_required = 1,
        ingredients =
        {
          {"rocket-part", 100},
        },
        result_count = 1000,
        result = "space-science-pack"
}})
table.insert(data.raw["technology"]["rocket-silo"].effects, {type = "unlock-recipe", recipe = "space-science-pack"})
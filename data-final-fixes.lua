-- Fixing Py Raw Ores duplicate item_group ordering for him
-- If any other mods have this issue, they won't be fixed
if mods["pyrawores"] then
    data.raw["item-group"]["py-rawores"].order = "x"
end
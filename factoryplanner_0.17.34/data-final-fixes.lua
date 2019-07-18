-- Fixing Py Raw Ores duplicate item_group ordering
-- If any other mods have this issue, it won't be fixed automatically
if mods["pyrawores"] then
    data.raw["item-group"]["py-rawores"].order = "y"
end
if mods["py-petroleum-handling"] then
    data.raw["item-group"]["py-petroleum-handling"].order = "x"
end